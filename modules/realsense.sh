#!/bin/bash

MODULE_NAME=realsense
MODULE_DEPS="opencv"
MODULE_DESC="Install librealsense and Python bindings"
MODULE_ASSET_DIR=${REALSENSE_ASSET_DIR:-${ASSET_DIR:-$HOME_DIR/uav_vision_pkg}}

check_realsense() {
    command -v rs-enumerate-devices >/dev/null 2>&1 ||
    ldconfig -p 2>/dev/null | grep -q librealsense2
}

install_realsense() {
    local home_dir=${HOME_DIR:-/home/nv}
    local asset_dir=$MODULE_ASSET_DIR
    local librealsense_dir=${LIBREALSENSE_DIR:-$home_dir/librealsense}
    local librealsense_zip=${LIBREALSENSE_ZIP:-$asset_dir/librealsense.zip}
    local jobs=${JOBS:-$(nproc)}

    ensure_dir_from_zip "$librealsense_dir" "$librealsense_zip" "$home_dir"

    if [ ! -d "$librealsense_dir" ]; then
        cd "$home_dir"
        git clone https://github.com/IntelRealSense/librealsense.git "$librealsense_dir"
    fi

    require_path "$librealsense_dir"

    sudo apt-get update
    sudo apt-get -y install git cmake libssl-dev libusb-1.0-0-dev pkg-config libgtk-3-dev libglfw3-dev libgl1-mesa-dev libglu1-mesa-dev

    mkdir -p "$librealsense_dir/build"
    cd "$librealsense_dir/build"
    cmake ..
    make -j"$jobs"
    sudo make install

    sudo cp "$librealsense_dir/config/99-realsense-libusb.rules" /etc/udev/rules.d/
    sudo udevadm control --reload-rules
    sudo udevadm trigger

    python3 -m pip install pyrealsense2
}
