#!/bin/bash

MODULE_NAME=fastlio_mid360s
MODULE_DEPS="ros usb_permissions"
MODULE_DESC="Build Livox SDK2 and FAST-LIO for MID-360"
MODULE_ASSET_DIR=${FASTLIO_ASSET_DIR:-${ASSET_DIR:-$HOME_DIR/20.04-fasterlio-ego-ros-mid360s}}

check_fastlio_mid360s() {
    local home_dir=${HOME_DIR:-/home/nv}

    [ -f "$home_dir/ros_ws/devel/setup.bash" ] &&
    [ -d "$home_dir/Livox-SDK2/build" ] &&
    [ -f "$home_dir/faster_lio/src/faster-lio/config/mid360.yaml" ]
}

install_fastlio_mid360s() {
    local home_dir=${HOME_DIR:-/home/nv}
    local asset_dir=$MODULE_ASSET_DIR
    local ros_ws="$home_dir/ros_ws"
    local livox_dir="$home_dir/Livox-SDK2"
    local faster_lio_dir="$home_dir/faster_lio"

    sudo apt-get -y install git cmake libgoogle-glog-dev ros-noetic-serial libeigen3-dev

    mkdir -p "$ros_ws/src"
    cd "$ros_ws/src"
    [ -d fcu_core ] || git clone https://ghfast.top/https://github.com/fancinnov/fcu_core.git
    [ -d quadrotor_msgs ] || git clone https://ghfast.top/https://github.com/fancinnov/quadrotor_msgs.git
    require_path "$asset_dir/fcu_core修改文件/fcu_bridge_001.cpp"
    cp "$asset_dir/fcu_core修改文件/fcu_bridge_001.cpp" fcu_core/src/fcu_bridge_001.cpp

    source /opt/ros/noetic/setup.bash
    cd "$ros_ws"
    catkin_make

    if [ ! -d "$livox_dir" ]; then
        require_path "$asset_dir/Livox-SDK2"
        cp -a "$asset_dir/Livox-SDK2" "$home_dir/"
    fi
    mkdir -p "$livox_dir/build"
    cd "$livox_dir/build"
    cmake ..
    make -j"${JOBS:-$(nproc)}"
    sudo make install

    if [ ! -d "$faster_lio_dir" ]; then
        require_path "$asset_dir/faster_lio"
        cp -a "$asset_dir/faster_lio" "$home_dir/"
    fi
    require_path "$asset_dir/mid360.yaml"
    require_path "$faster_lio_dir/src/faster-lio/config"
    cp "$asset_dir/mid360.yaml" "$faster_lio_dir/src/faster-lio/config/"

    cd "$faster_lio_dir/src/livox_ros_driver2"
    ./build.sh ROS1
}
