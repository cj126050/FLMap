# Mid360-LIO 使用说明书（简明版）

> 适用仓库：`mid360_lio`（Livox Mid360 实时激光惯性建图）
> 环境：Ubuntu 22.04 + ROS 2 Humble + Livox-SDK2

---

## 〇、一次性准备（首次使用前做一次）

1. **接好硬件**：用网线连接 Mid360 转接盒的 RJ45 口 → 电脑有线网口。

2. **配电脑静态 IP**（雷达网段，本项目为 `192.168.120.x`）：

   ```bash
   ip -br addr show                 # 找到有线网卡名，如 enp131s0
   sudo nmcli connection add type ethernet ifname <网卡名> \
     con-name mid360 ipv4.method manual ipv4.addresses 192.168.120.10/24
   sudo nmcli connection up mid360
   ```

3. **确认雷达可达**：

   ```bash
   ping -c 2 192.168.120.221        # 0% 丢包即正常
   ```

4. **编译工作空间**（在仓库根目录执行一次）：

   ```bash
   cd ~/mid360_lio
   ./setup.sh
   ```

---

## 一、一键启动（推荐）

```bash
cd ~/mid360_lio
./scripts/mid360_control.sh
```

脚本会自动依次启动：**Livox 驱动 → FAST-LIO2 建图 → RViz 可视化**，
随后进入交互式命令行，光标停在 `mid360>` 提示符处等你输入命令。

启动参数：

| 命令 | 说明 |
|---|---|
| `./scripts/mid360_control.sh` | 完整流程（自动开 RViz） |
| `./scripts/mid360_control.sh norviz` | 不开 RViz（远程 / 无人值守） |

---

## 二、分开启动（逐条手动，适合排查问题）

开 **4 个终端**，每个终端先执行：

```bash
cd ~/mid360_lio
source install/setup.bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
```

然后分别在 4 个终端运行：

| 终端 | 命令 | 作用 |
|---|---|---|
| ① 驱动 | `ros2 launch livox_ros_driver2 msg_MID360.launch.py` | 实时采集点云 + IMU |
| ② 建图 | `ros2 launch go2_fastlio mapping_mid360_go2.launch.py use_sim_time:=false` | 实时建图 |
| ③ 可视化 | `ros2 launch go2_fastlio rviz.launch.py` | RViz 预览 |
| ④ 录包 | `ros2 bag record -o ~/bags/my_scan /livox/lidar /livox/imu /cloud_registered /aft_mapped_to_init` | 边录边存 |

> 停止：按 `Ctrl+C` 依次结束各终端。录包结束后可用
> `python3 scripts/bag_to_pcd.py <bag目录> <输出.pcd>` 单独转地图。

---

## 三、程序操作按键指南

进入交互式控制台后，在 `mid360>` 提示符输入以下命令（英文，回车执行）：

| 按键命令 | 功能 |
|---|---|
| `start` | 开始新扫描：在 `~/bags/` 下新建「开始时间」目录，并启动录包 |
| `pause` | 暂停录包（挂起 rosbag 进程，不丢数据） |
| `resume` | 继续录包 |
| `stop` | 停止录包，并自动把点云转成 `map.pcd` |
| `status` | 查看当前状态（各进程 PID、录包状态、已建目录） |
| `env` | 手动执行一次环境检查 |
| `help` | 显示命令列表 |
| `quit` | 退出整个程序（自动 stop + 关闭驱动/建图/RViz） |
| `Ctrl+C` | 紧急退出（等同 quit 的清理流程） |

### 首次启动的环境检查

第一次输入 `start` 时，程序会询问是否做环境检查：

```text
首次扫描前，是否需要做一次环境检查？
  (y) 是 —— 扫描本机环境，判断是否满足实时建图要求
  (n) 否 —— 跳过，直接开始扫描
是否检查环境 [y/N]:
```

- 输入 `y` 回车 → 自动检查 ROS 2、编译产物、Livox-SDK2、依赖库、雷达网络连通性等；
  不满足的项会归类列出，并给出补齐命令。
- 输入 `n` 或直接回车 → 跳过检查，直接开始扫描。
- 之后想复查，随时输入 `env` 命令，或单独运行 `./scripts/env_check.sh`。

### 典型操作流程

```text
mid360> start      ← 开始扫描（首次会询问是否做环境检查）
mid360> pause      ← 临时暂停录包
mid360> resume     ← 继续录包
mid360> stop       ← 结束本次任务，自动导出 map.pcd
mid360> start      ← 再开始下一次扫描（会新建另一个时间目录）
mid360> quit       ← 全部结束
```

### 每次任务产出目录

```
~/bags/2026-10-17_21-49-24/
├── info.txt       # 任务信息（开始时间、雷达 IP、录包话题）
├── map.pcd        # 建图结果（可导入 CloudCompare 查看）
├── record.log     # 录包日志
└── scan/          # 原始 rosbag（metadata.yaml + *.db3）
```

---

## 四、常见问题

| 现象 | 处理 |
|---|---|
| RViz 无点云 | 检查有线网卡 IP 是否为 `192.168.120.10`，`ping 192.168.120.221` 是否通 |
| 提示找不到 `install/setup.bash` | 先运行 `./setup.sh` 编译 |
| 点云偶尔漂移 | 内置断流保护会自动处理（`dt>0.2s` 不积分 + 速度护栏），详见 `docs/gap-fix.md` |
| PCD 转换失败 | 检查该次任务的 `record.log`，确认 `/cloud_registered` 有数据 |
| 想不录像只看图 | 用 `mid360_control.sh` 的 `start` 前不改动即可；或参考「分开启动」跳过终端④ |
