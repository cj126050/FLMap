#!/bin/bash
# Mid360-LIO 一键编译脚本
# 用法: ./setup.sh   （在仓库根目录执行）
set -e

echo "=== Mid360-LIO 编译脚本 ==="

# 检查 ROS 2 Humble
if [ -z "$ROS_DISTRO" ]; then
    if [ -f /opt/ros/humble/setup.bash ]; then
        source /opt/ros/humble/setup.bash
    else
        echo "[ERROR] 未找到 ROS 2 Humble，请先安装:"
        echo "  https://docs.ros.org/en/humble/Installation.html"
        exit 1
    fi
fi

if [ "$ROS_DISTRO" != "humble" ]; then
    echo "[WARN] 当前 ROS_DISTRO=$ROS_DISTRO，本工程在 humble 上验证过"
fi

# 检查 Livox-SDK2
if [ ! -f /usr/local/lib/liblivox_lidar_sdk_shared.so ]; then
    echo "[WARN] 未找到 Livox-SDK2 (/usr/local/lib/liblivox_lidar_sdk_shared.so)"
    echo "       请先安装: https://github.com/Livox-SDK/Livox-SDK2"
    echo "       安装完成后重新运行本脚本"
fi

# 编译
echo "=== colcon build --symlink-install ==="

# 兼容性：确保 CMake 用系统 python（有 catkin_pkg 的那个）。
# 若用户用 pyenv/conda 等，PATH 里的 python3 可能缺少 ROS 依赖，导致 package.xml 解析失败。
if [ -x /usr/bin/python3 ] && /usr/bin/python3 -c "import catkin_pkg" 2>/dev/null; then
    export PATH="/usr/bin:$PATH"
    export PYTHON_EXECUTABLE=/usr/bin/python3
    export Python3_EXECUTABLE=/usr/bin/python3
fi

colcon build --symlink-install

echo ""
echo "=== 编译完成 ==="
echo "  在每次新终端使用前执行:"
echo "    source $(pwd)/install/setup.bash"
echo ""
echo "  开始实时建图:"
echo "    ./scripts/mid360_control.sh"
