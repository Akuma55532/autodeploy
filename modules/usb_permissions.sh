#!/bin/bash

MODULE_NAME=usb_permissions
MODULE_DEPS=""
MODULE_DESC="Install 70-ttyusb udev permissions"
# The udev rule is distributed with autodeploy under packs/.
# USB_PERMISSIONS_ASSET_DIR can be set to use a different rule package.
MODULE_ASSET_DIR=${USB_PERMISSIONS_ASSET_DIR:-$ROOT_DIR/packs}

check_usb_permissions() {
    [ -f /etc/udev/rules.d/70-ttyusb.rules ]
}

install_usb_permissions() {
    local rules_file="$MODULE_ASSET_DIR/70-ttyusb.rules"

    require_path "$rules_file"
    sudo cp "$rules_file" /etc/udev/rules.d/
}
