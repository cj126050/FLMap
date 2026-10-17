# Mid360-LIO：Livox Mid360 实时激光惯性建图

一个**自包含**的 ROS 2 (Humble) 工作空间，用于 **Mid360 固态激光雷达实时建图**，附带交互式控制台和针对数据断流的鲁棒性修复。

> 📘 English: [README.md](README.md)

## 特性

- **实时建图** — Livox 驱动直接发布点云 + IMU 给 `fastlio2_mapping`，无需 rosbag。
- **交互式控制台** — 在终端用 `start` / `pause` / `resume` / `stop` 控制扫描。
- **自动 RViz** — 控制器启动时自动打开 RViz 可视化。
- **自动导出 PCD** — 每次扫描自动生成 `.pcd` 地图。
- **断流鲁棒** — 修复雷达/IMU 数据断流导致的点云发散（详见 [docs/gap-fix.md](docs/gap-fix.md)）。
- **一键安装** — `setup.sh` 编译整个工作空间。

## 架构

```
Mid360 雷达 ──(网线)──▶ livox_ros_driver2 ──▶ /livox/lidar (CustomMsg)
                                        └────▶ /livox/imu
                                                    │
                                                    ▼
                                          fastlio2_mapping (FAST-LIO2)
                                                    │
                              ┌─────────────────────┼─────────────────────┐
                              ▼                     ▼                     ▼
                        /cloud_registered   /aft_mapped_to_init      RViz2
                              │
                        bag_to_pcd.py ──▶ map.pcd
```

## 包说明

| 包 | 作用 | 上游 |
|---|---|---|
| `FAST_LIO2_ROS2` (`fast_lio2`) | 核心 LIO 算法（含断流修复） | [Vulcan-YJX/FAST_LIO2_ROS2](https://github.com/Vulcan-YJX/FAST_LIO2_ROS2) |
| `livox_ros_driver2` | Livox Mid360 驱动 (ROS 2) | [Livox-SDK/livox_ros_driver2](https://github.com/Livox-SDK/livox_ros_driver2) |
| `go2_fastlio` | launch / config 集成包 | 本仓库 |

## 依赖

- Ubuntu 22.04
- ROS 2 Humble（完整桌面版）
- Livox-SDK2（`/usr/local/lib/liblivox_lidar_sdk_shared.so`）
- `libpcl-dev`、`eigen3`、`sophus`

```bash
sudo apt update
sudo apt install -y ros-humble-desktop libpcl-dev ros-humble-pcl-ros \
  ros-humble-tf2 ros-humble-tf2-ros ros-humble-message-filters \
  libeigen3-dev ros-humble-nav-msgs ros-humble-visualization-msgs
```

## 编译

```bash
cd mid360_lio
./setup.sh              # 一键编译工作空间
```

或手动：

```bash
cd mid360_lio
source /opt/ros/humble/setup.bash
colcon build --symlink-install
source install/setup.bash
```

## 网络配置（一次性）

1. 用**网线**连接 Mid360（转接盒 RJ45 口）到电脑有线网口。
2. 给电脑有线网卡配雷达网段的静态 IP：

```bash
ip -br addr show                     # 找有线接口名（如 enp131s0）
sudo nmcli connection add type ethernet ifname <接口名> \
  con-name mid360 ipv4.method manual ipv4.addresses 192.168.120.10/24
sudo nmcli connection up mid360
```

3. 编辑 `src/livox_ros_driver2/config/MID360_config.json`：
   - `host_net_info.*_ip` → 电脑静态 IP（如 `192.168.120.10`）
   - `lidar_configs[0].ip` → 雷达 IP（如 `192.168.120.221`）

4. 验证：

```bash
ping -c 2 192.168.120.221     # 应返回 0% 丢包
```

> 配置文件通过 `--symlink-install` 安装，改源码即生效，无需重新编译。

## 使用

### 交互式控制台（推荐）

```bash
cd mid360_lio
./scripts/mid360_control.sh              # 完整流程（自动 RViz）
./scripts/mid360_control.sh norviz       # 不开 RViz（远程/无人值守）
```

控制台命令：

| 命令 | 作用 |
|---|---|
| `start` | 开始新扫描：在 `~/bags/` 下建时间戳目录并启动录包 |
| `pause` | 暂停录包（挂起 rosbag 进程，不丢数据） |
| `resume` | 继续录包 |
| `stop` | 停止录包并自动导出 PCD |
| `status` | 查看状态 |
| `quit` | 退出（自动 stop + 关闭驱动/建图/RViz） |
| `help` | 命令列表 |

每次任务产出：

```
~/bags/2026-10-17_21-49-24/
├── info.txt       # 任务信息
├── map.pcd        # 建图结果
├── record.log     # 录包日志
└── scan/          # 原始 rosbag
    ├── metadata.yaml
    └── scan_0.db3
```

### 离线回放（rosbag → 建图）

```bash
source install/setup.bash
ros2 bag play /path/to/bag
ros2 launch go2_fastlio mapping_mid360_go2.launch.py use_sim_time:=true
```

## 断流鲁棒性修复

原生 FAST-LIO2 在雷达+IMU 数据流出现断档时（录制丢数据或网络抖动）会发散：跨断档的一步 IMU 积分会积出数 m/s 的虚假速度，点云向一个方向"飞走"。

本仓库包含三处针对性修复（完整分析见 [docs/gap-fix.md](docs/gap-fix.md)）：

1. **断档检测**（`IMU_Processing.cpp`）— `dt > 0.2 s` 时跳过积分、保持位姿、清零速度，并**放大位置/速度协方差**，让 EKF 重新信任下一次激光匹配。
2. **速度护栏**（`LIVMapper.cpp`）— `|v| > 3 m/s` 时钳制，作为发散的最后防线。
3. **删除调试打印**（`voxel_map.cpp`）— 移除逐点调试打印（曾产生 100+ MB 日志，且是越界隐患）。

## 许可

[BSD-3-Clause](LICENSE)。`FAST_LIO2_ROS2` 与 `livox_ros_driver2` 保留各自上游 BSD 许可。
