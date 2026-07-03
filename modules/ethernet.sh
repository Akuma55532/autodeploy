#!/bin/bash

MODULE_NAME=ethernet
MODULE_DEPS=""
MODULE_DESC="Install external Ethernet drivers"

check_ethernet() {
    modinfo r8125 >/dev/null 2>&1
}

install_ethernet() {
    local home_dir=${HOME_DIR:-/home/nv}
    local asset_dir=${ASSET_DIR:-$home_dir/JetsonNXyolo}
    local driver_archive=${ETHERNET_DRIVER_ARCHIVE:-$asset_dir/r8125-9.015.00.tar.bz2}
    local driver_dir=${ETHERNET_DRIVER_DIR:-$home_dir/r8125-9.015.00}

    ensure_dir_from_tbz2 "$driver_dir" "$driver_archive" "$home_dir"
    require_path "$driver_dir"

    sudo apt-get update
    sudo apt-get -y install build-essential

    cd "$driver_dir"
    sudo ./autorun.sh
}
