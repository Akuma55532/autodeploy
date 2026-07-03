#!/bin/bash

MODULE_NAME=ros
MODULE_DEPS=""
MODULE_DESC="Install ROS1 by FishROS"

ros_run_fishros_with_answers() {
    local fishros_script=$1
    local answers=$2
    local input_delay=${FISHROS_INPUT_DELAY:-5}
    local fifo
    local writer_pid

    if [ -z "$answers" ]; then
        echo "FishROS answers are empty."
        return 1
    fi

    fifo=$(mktemp -u)
    mkfifo "$fifo" || return 1

    {
        while IFS= read -r answer; do
            echo "Auto input after ${input_delay}s: $answer"
            sleep "$input_delay"
            printf '%s\n' "$answer"
        done <<< "$answers"
    } > "$fifo" &
    writer_pid=$!

    bash "$fishros_script" < "$fifo"
    local script_status=$?

    wait "$writer_pid" 2>/dev/null
    rm -f "$fifo"

    return "$script_status"
}

check_ros() {
    command -v roscore >/dev/null 2>&1
}

install_ros() {
    local install_ros_with_fishros=${INSTALL_ROS_WITH_FISHROS:-1}
    local fishros_auto_feed=${FISHROS_AUTO_FEED:-1}
    local fishros_answers=${FISHROS_ROS_ANSWERS:-$'1\n1\n2\n1\n1\n3\n1'}
    local install_dir=${FISHROS_INSTALL_DIR:-/tmp/fishros-autodeploy}
    local fishros_script="$install_dir/fishros"

    if check_ros; then
        echo "ROS1 already exists, skipping FishROS install."
        return 0
    fi

    if [ "$install_ros_with_fishros" != "1" ]; then
        echo "ROS1 not found and FishROS install is disabled."
        return 1
    fi

    mkdir -p "$install_dir"
    cd "$install_dir"
    rm -f /tmp/fish_install.yaml
    wget http://fishros.com/install -O "$fishros_script"

    if [ "$fishros_auto_feed" = "1" ]; then
        ros_run_fishros_with_answers "$fishros_script" "$fishros_answers"
    else
        bash "$fishros_script"
    fi
}
