# Mid360-LIO: Real-time LiDAR-Inertial Odometry & Mapping for Livox Mid360

A complete, self-contained ROS 2 (Humble) workspace for **real-time** FAST-LIO2 mapping
with the Livox Mid360 solid-state LiDAR, plus an interactive console controller and
robustness fixes for sensor data-stream gaps.

> 📘 中文文档见 [README_zh.md](README_zh.md)

## Features

- **Real-time mapping** — Livox driver publishes raw point cloud + IMU directly to `fastlio2_mapping`, no rosbag required.
- **Interactive console** — control scanning with `start` / `pause` / `resume` / `stop` commands in the terminal.
- **Auto RViz** — RViz visualization launches automatically when the controller starts.
- **Auto PCD export** — each scan automatically produces a `.pcd` map.
- **Gap-resilient LIO** — fixes for radar/IMU data-stream gaps that previously caused point-cloud divergence (see [docs/gap-fix.md](docs/gap-fix.md)).
- **One-key install** — `setup.sh` builds the whole workspace.

## Architecture

```
Mid360 LiDAR ──(ethernet)──▶ livox_ros_driver2 ──▶ /livox/lidar (CustomMsg)
                                          └─────▶ /livox/imu
                                                        │
                                                        ▼
                                              fastlio2_mapping (FAST-LIO2)
                                                        │
                                    ┌───────────────────┼───────────────────┐
                                    ▼                   ▼                   ▼
                              /cloud_registered   /aft_mapped_to_init    RViz2
                                    │
                              bag_to_pcd.py ──▶ map.pcd
```

## Packages

| Package | Role | Upstream |
|---|---|---|
| `FAST_LIO2_ROS2` (`fast_lio2`) | Core LIO algorithm (with gap-fix patches) | [Vulcan-YJX/FAST_LIO2_ROS2](https://github.com/Vulcan-YJX/FAST_LIO2_ROS2) |
| `livox_ros_driver2` | Livox Mid360 driver (ROS 2) | [Livox-SDK/livox_ros_driver2](https://github.com/Livox-SDK/livox_ros_driver2) |
| `go2_fastlio` | Launch / config integration package | this repo |

## Prerequisites

- Ubuntu 22.04
- ROS 2 Humble (full desktop)
- Livox-SDK2 installed (`/usr/local/lib/liblivox_lidar_sdk_shared.so`)
- `libpcl-dev`, `eigen3`, `sophus`

```bash
sudo apt update
sudo apt install -y ros-humble-desktop libpcl-dev ros-humble-pcl-ros \
  ros-humble-tf2 ros-humble-tf2-ros ros-humble-message-filters \
  libeigen3-dev ros-humble-nav-msgs ros-humble-visualization-msgs
```

## Build

```bash
cd mid360_lio
./setup.sh              # colcon build the workspace
```

Or manually:

```bash
cd mid360_lio
source /opt/ros/humble/setup.bash
colcon build --symlink-install
source install/setup.bash
```

## Network setup (once)

1. Connect the Mid360 to the PC via **ethernet** (the adapter box RJ45 port).
2. Configure the PC wired NIC with a static IP on the LiDAR's subnet:

```bash
ip -br addr show                     # find your wired interface name (e.g. enp131s0)
sudo nmcli connection add type ethernet ifname <ifname> \
  con-name mid360 ipv4.method manual ipv4.addresses 192.168.120.10/24
sudo nmcli connection up mid360
```

3. Edit `src/livox_ros_driver2/config/MID360_config.json`:
   - `host_net_info.*_ip` → your PC static IP (e.g. `192.168.120.10`)
   - `lidar_configs[0].ip` → your LiDAR IP (e.g. `192.168.120.221`)

4. Verify:

```bash
ping -c 2 192.168.120.221     # should return 0% loss
```

> Note: the config file is installed via `--symlink-install`, so editing the source file
> takes effect immediately — no rebuild needed.

## Usage

### Interactive console (recommended)

```bash
cd mid360_lio
./scripts/mid360_control.sh              # full flow (auto RViz)
./scripts/mid360_control.sh norviz       # no RViz (headless / remote)
```

Commands inside the console:

| Command | Action |
|---|---|
| `start` | Begin a new scan — creates a timestamped task dir under `~/bags/` and starts recording |
| `pause` | Pause recording (rosbag process suspended, no data loss) |
| `resume` | Resume recording |
| `stop` | Stop recording and auto-export PCD |
| `status` | Show current state |
| `quit` | Exit (auto stop + shutdown driver/mapping/RViz) |
| `help` | List commands |

Each task produces:

```
~/bags/2026-10-17_21-49-24/
├── info.txt       # task metadata
├── map.pcd        # mapping result
├── record.log     # recording log
└── scan/          # raw rosbag
    ├── metadata.yaml
    └── scan_0.db3
```

### Offline replay (rosbag → map)

```bash
source install/setup.bash
ros2 bag play /path/to/bag
ros2 launch go2_fastlio mapping_mid360_go2.launch.py use_sim_time:=true
```

## Gap-resilience fixes

The stock FAST-LIO2 diverges when the radar+IMU stream has gaps (recorded data or network
dropouts): a single IMU integration step across the gap produces a spurious velocity of
several m/s, and the point cloud "flies away" in one direction.

This repo ships three targeted fixes (see [docs/gap-fix.md](docs/gap-fix.md) for full analysis):

1. **Gap detection** (`IMU_Processing.cpp`) — `dt > 0.2 s` → skip integration, hold pose, zero velocity, and **inflate position/velocity covariance** so the EKF re-trusts the next lidar match.
2. **Velocity guard** (`LIVMapper.cpp`) — clamp `|v| > 3 m/s` as a last-resort divergence guard.
3. **Debug-print removal** (`voxel_map.cpp`) — removed a per-iteration debug print that produced 100+ MB logs and was an out-of-bounds hazard.

## License

[BSD-3-Clause](LICENSE). `FAST_LIO2_ROS2` and `livox_ros_driver2` retain their original upstream licenses (BSD).
