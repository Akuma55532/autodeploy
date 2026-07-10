#!/bin/bash

MODULE_NAME=usb_permissions
MODULE_DEPS=""
MODULE_DESC="Install 70-ttyusb udev permissions"
MODULE_ASSET_DIR=${USB_PERMISSIONS_ASSET_DIR:-${ASSET_DIR:-}}
if [ -z "$MODULE_ASSET_DIR" ]; then
    for MODULE_ASSET_DIR in "$HOME_DIR/20.04-vins-ego-ros" "$HOME_DIR/20.04-fasterlio-ego-ros-mid360s"; do
        [ -d "$MODULE_ASSET_DIR" ] && break
    done
fi

check_usb_permissions() {
    [ -f /etc/udev/rules.d/70-ttyusb.rules ]
}

install_usb_permissions() {
    local rules_file="$MODULE_ASSET_DIR/70-ttyusb.rules"

    require_path "$rules_file"
    sudo cp "$rules_file" /etc/udev/rules.d/
}
