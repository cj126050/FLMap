# 建图操作说明（离线 + 实时）

## 一、离线建图（录制 rosbag → PC 回放重建）

```bash
# 终端 1：回放 bag（按需加 --rate 倍速）
source install/setup.bash
ros2 bag play ~/bags/xxx_bag

# 终端 2：建图（离线回放必须 use_sim_time:=true）
source install/setup.bash
ros2 launch go2_fastlio mapping_mid360_go2.launch.py use_sim_time:=true

# 终端 3（可选）：RViz 预览
ros2 launch go2_fastlio rviz.launch.py
```

## 二、实时建图（雷达直连，边采集边建图）

详见 [README_zh.md](../README_zh.md) 的「使用」章节。核心：

```bash
./scripts/mid360_control.sh
# 控制台内: start / pause / resume / stop / quit
```

## 三、地图保存为 PCD

本分支 FAST-LIO2 的内置 `pcd_save_en` 是**死代码**（`LIVMapper.cpp` 的 RGB 点云创建后从未填充），所以建图节点不会自动落盘 PCD。

正确做法：录制 `/cloud_registered`，再离线转换：

```bash
# 实时建图：控制器 stop 时已自动调用此脚本
# 离线建图：手动录包后转换
source install/setup.bash
python3 scripts/bag_to_pcd.py <bag目录> <输出.pcd>
```

或用 rosbag 录包 + 转换：

```bash
ros2 bag record -o map_rec /cloud_registered
python3 scripts/bag_to_pcd.py map_rec map.pcd
pcl_viewer map.pcd    # 查看
```

## 四、常用故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| 驱动 `init lidar failed` | IP 不在同一网段 | `ip -br addr` + `ping <雷达IP>` |
| ping 通但无话题 | 配置里雷达 IP 不符 | 改 `MID360_config.json` 的 `lidar_configs[0].ip` |
| 实时点云飞走 | `use_sim_time` 没关 | 实时必须 `use_sim_time:=false` |
| 速度反复冲高 / vel-guard 触发 | 数据断流 | 查网线/供电；换网线；勿走 WiFi |
| 建图一直 `No point!!!` | 话题名不匹配 | `ros2 topic list` 确认 `/livox/lidar`、`/livox/imu` |
| livox 库错误 | SDK 库路径 | `export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib` |

## 五、关键参数备忘

- `data_src = 0`（实时采集，**不是 1**）；`2` 为文件回放
- `xfer_format = 1`（CustomMsg，Mid360 必须）；`0` 为 PointCloud2
- 配置参数名是 `user_config_path`（不是 `config_file`）
- 实时建图 `use_sim_time:=false`；离线回放用默认 `true`
- RMW: `rmw_cyclonedds_cpp`，`ROS_DOMAIN_ID=0`
