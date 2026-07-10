#!/bin/bash

MODULE_NAME=vins_ego
MODULE_DEPS="ros realsense usb_permissions"
MODULE_DESC="Build VINS-EGO ROS workspaces and planners"
MODULE_ASSET_DIR=${VINS_EGO_ASSET_DIR:-${ASSET_DIR:-$HOME_DIR/20.04-vins-ego-ros}}

check_vins_ego() {
    local home_dir=${HOME_DIR:-/home/nv}

    [ -f "$home_dir/ros_ws/devel/setup.bash" ] &&
    [ -f "$home_dir/realsense_ws/devel/setup.bash" ] &&
    [ -f "$home_dir/catkin_pkg/devel/setup.bash" ] &&
    [ -f "$home_dir/vins-fusion-gpu/devel/setup.bash" ] &&
    [ -f "$home_dir/ego-planner/devel/setup.bash" ]
}

install_vins_ego() {
    local home_dir=${HOME_DIR:-/home/nv}
    local asset_dir=$MODULE_ASSET_DIR
    local ros_ws="$home_dir/ros_ws"
    local deps_dir="$asset_dir/其它依赖库"
    local ceres_dir="$home_dir/ceres-solver-1.14.0"
    local jobs=${JOBS:-$(nproc)}

    sudo apt-get -y install ros-noetic-serial ros-noetic-ddynamic-reconfigure \
        ros-noetic-cv-bridge ros-noetic-cmake-modules libeigen3-dev \
        libgoogle-glog-dev libgflags-dev libatlas-base-dev libarmadillo-dev

    mkdir -p "$ros_ws/src"
    cd "$ros_ws/src"
    [ -d fcu_core ] || git clone https://ghfast.top/https://github.com/fancinnov/fcu_core.git
    [ -d quadrotor_msgs ] || git clone https://ghfast.top/https://github.com/fancinnov/quadrotor_msgs.git
    require_path "$asset_dir/fcu_core修改文件/fcu_bridge_001.cpp"
    cp "$asset_dir/fcu_core修改文件/fcu_bridge_001.cpp" fcu_core/src/fcu_bridge_001.cpp

    source /opt/ros/noetic/setup.bash
    cd "$ros_ws"
    catkin_make
    if [ ! -d "$home_dir/realsense_ws" ]; then
        require_path "$asset_dir/realsense_ws"
        cp -a "$asset_dir/realsense_ws" "$home_dir/"
    fi
    cd "$home_dir/realsense_ws"
    catkin_make

    if [ ! -d "$home_dir/catkin_pkg" ]; then
        require_path "$deps_dir/catkin_pkg"
        cp -a "$deps_dir/catkin_pkg" "$home_dir/"
    fi
    cd "$home_dir/catkin_pkg"
    catkin_make
    append_if_missing "source $home_dir/catkin_pkg/devel/setup.bash" "$home_dir/.bashrc"

    ensure_dir_from_zip "$ceres_dir" "$deps_dir/ceres-solver-1.14.0.zip" "$home_dir"
    require_path "$ceres_dir"
    mkdir -p "$ceres_dir/build"
    cd "$ceres_dir/build"
    cmake ..
    sudo make install -j"$jobs"

    if [ ! -d "$home_dir/vins-fusion-gpu" ]; then
        require_path "$asset_dir/vins-fusion-gpu"
        cp -a "$asset_dir/vins-fusion-gpu" "$home_dir/"
    fi
    cd "$home_dir/vins-fusion-gpu"
    catkin_make

    if [ ! -d "$home_dir/ego-planner" ]; then
        require_path "$asset_dir/ego-planner"
        cp -a "$asset_dir/ego-planner" "$home_dir/"
    fi
    cd "$home_dir/ego-planner"
    catkin_make -DCMAKE_BUILD_TYPE=Release
}
