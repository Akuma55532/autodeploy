#!/bin/bash

# 默认起始步骤
START_STEP=${1:-1}
INSTALL_ROS_WITH_FISHROS=${INSTALL_ROS_WITH_FISHROS:-1}
FISHROS_AUTO_FEED=${FISHROS_AUTO_FEED:-1}
FISHROS_INPUT_DELAY=${FISHROS_INPUT_DELAY:-5}
FISHROS_ROS_ANSWERS=${FISHROS_ROS_ANSWERS:-$'1\n1\n2\n2\n3\n1\n3\n1'}
PACKAGE_DIR=/home/nv/20.04-vins-ego-swarm

if [ ! -d "$PACKAGE_DIR" ]; then
    error_time=$(date '+%Y-%m-%d %H:%M:%S')
    error_msg="Error: VINS-EGO package directory not found: $PACKAGE_DIR at $error_time"
    echo "$error_msg" | tee -a /home/nv/install_errors.txt
    echo "Please extract the complete package to /home/nv/20.04-vins-ego-swarm, then rerun." | tee -a /home/nv/install_errors.txt
    exit 1
fi

echo "Starting VINS-ROS-EGO deployment from step $START_STEP..."

# Function to check last command result
check_error() {
    if [ $? -ne 0 ]; then
        local error_time=$(date '+%Y-%m-%d %H:%M:%S')
        local error_msg="Error: Step $1 failed at $error_time"
        echo "$error_msg" | tee -a /home/nv/install_errors.txt
        echo "Exiting." | tee -a /home/nv/install_errors.txt
        exit 1
    else
        echo "Step $1 completed successfully."
    fi
}

# Function to check if current step should be executed
should_execute_step() {
    local step_num=$1
    # Convert to number for comparison (in case of decimal steps like 2.1)
    if (( $(echo "$step_num >= $START_STEP" | bc -l) )); then
        return 0  # Should execute
    else
        return 1  # Should skip
    fi
}

run_fishros_with_answers() {
    local answers=$1
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
            echo "Auto input after ${FISHROS_INPUT_DELAY}s: $answer"
            sleep "$FISHROS_INPUT_DELAY"
            printf '%s\n' "$answer"
        done <<< "$answers"
    } > "$fifo" &
    writer_pid=$!

    bash fishros < "$fifo"
    local script_status=$?

    wait "$writer_pid" 2>/dev/null
    rm -f "$fifo"

    return "$script_status"
}

# Step 1.1: ROS1 / FishROS
if should_execute_step 1.1; then
    echo "Step 1.1: Checking ROS1..."
    if command -v roscore >/dev/null 2>&1; then
        echo "ROS1 already exists, skipping FishROS install."
    elif [ "$INSTALL_ROS_WITH_FISHROS" = "1" ]; then
        cd /tmp || exit 1
        rm -f /tmp/fish_install.yaml
        wget http://fishros.com/install -O fishros
        check_error "1.1.1"
        if [ "$FISHROS_AUTO_FEED" = "1" ]; then
            run_fishros_with_answers "$FISHROS_ROS_ANSWERS"
            check_error "1.1.2"
        else
            bash fishros
            check_error "1.1.2"
            echo "FishROS is interactive. Set FISHROS_AUTO_FEED=1 to automate it."
        fi
    else
        echo "ROS1 not found. Set INSTALL_ROS_WITH_FISHROS=1, then rerun from step 1.2."
        exit 1
    fi
fi

# Step 1.2: create the ROS workspace
if should_execute_step 1.2; then
    echo "Step 1.2: Creating ROS workspace..."
    mkdir -p /home/nv/ros_ws/src
    cd /home/nv/ros_ws/src
    check_error "1.2"
    echo "Created ROS workspace at /home/nv/ros_ws/src"
else
    echo "Skipping Step 1.2: Creating ROS workspace..."
    cd /home/nv/ros_ws/src
fi

# Step 2: clone the repository
if should_execute_step 2.1; then
    echo "Step 2.1: Cloning repositories..."
    git clone https://ghfast.top/https://github.com/fancinnov/fcu_core_v2.git
    git clone https://ghfast.top/https://github.com/fancinnov/quadrotor_msgs.git
    git clone https://ghfast.top/https://github.com/fancinnov/fcu_core_rviz_swarm_goals_plugin.git
    git clone https://ghfast.top/https://github.com/fancinnov/FanciSwarm_urdf.git
    check_error "2.1"
fi

if should_execute_step 2.3; then
    sudo apt-get -y install ros-noetic-serial libeigen3-dev 
    check_error "2.3"
fi

# Step 3: build the workspace
if should_execute_step 3; then
    echo "Step 3: Building ROS workspace..."
    cd /home/nv/ros_ws
    source /opt/ros/noetic/setup.bash
    catkin_make
    check_error "3"
    echo "Built the ROS workspace."
else
    echo "Skipping Step 3: Building ROS workspace..."
    cd /home/nv/ros_ws
    source /opt/ros/noetic/setup.bash
fi

# Step 4: chmod the usb permissions
if should_execute_step 4; then
    echo "Step 4: Setting USB permissions..."
    sudo cp /home/nv/20.04-vins-ego-swarm/70-ttyusb.rules /etc/udev/rules.d/
    check_error "4"
else
    echo "Skipping Step 4: Setting USB permissions..."
fi

# Step 5: install nvidia jetpack
if should_execute_step 5.1; then
    echo "Step 5: Installing NVIDIA Jetpack..."
    echo "deb http://repo.download.nvidia.com/jetson/common r35.4 main" | sudo tee -a /etc/apt/sources.list.d/nvidia-l4t-apt-source.list > /dev/null
    check_error "5.1"
fi

if should_execute_step 5.2; then
    echo "deb http://repo.download.nvidia.com/jetson/t234 r35.4 main" | sudo tee -a /etc/apt/sources.list.d/nvidia-l4t-apt-source.list > /dev/null
    check_error "5.2"
fi

if should_execute_step 5.3; then
    sudo apt update
    check_error "5.3"
fi

if should_execute_step 5.4; then
    sudo apt -y install nvidia-jetpack
    check_error "5.4"
fi

if should_execute_step 5.5; then
    cat >> ~/.bashrc <<EOF

# CUDA environment variables
export CUDA_HOME=/usr/local/cuda
export PATH=\$CUDA_HOME/bin:\$PATH
export LD_LIBRARY_PATH=\$CUDA_HOME/lib64:\$LD_LIBRARY_PATH
EOF
    # Make CUDA available to commands that run later in this deployment.
    export CUDA_HOME=/usr/local/cuda
    export PATH="$CUDA_HOME/bin:$PATH"
    export LD_LIBRARY_PATH="$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}"
    check_error "5.5"
fi

if should_execute_step 5.6; then
    cd /usr/include && sudo cp cudnn* /usr/local/cuda/include 
    check_error "5.6"
fi

if should_execute_step 5.7; then
    cd /usr/lib/aarch64-linux-gnu && sudo cp libcudnn* /usr/local/cuda/lib64 
    check_error "5.7"
fi

if should_execute_step 5.8; then
    sudo apt -y install python3-pip 
    # Do not use the unqualified `pip`: it can be absent or point to a
    # different Python installation, leaving the `jtop` executable missing.
    sudo -H python3 -m pip install -U pip
    sudo -H python3 -m pip install jetson-stats
    check_error "5.8"
fi


# step 6: install librealsense
if should_execute_step 6.1; then
    echo "Step 6: Installing librealsense..."
    unzip /home/nv/20.04-vins-ego-swarm/其它依赖库/librealsense -d /home/nv/
    check_error "6.1"
fi

if should_execute_step 6.2; then
    sudo apt-get update
    check_error "6.2"
fi

if should_execute_step 6.3; then
    sudo apt-get -y install git cmake libssl-dev libusb-1.0-0-dev pkg-config libgtk-3-dev
    check_error "6.3"
fi

if should_execute_step 6.4; then
    sudo apt-get -y install libglfw3-dev libgl1-mesa-dev libglu1-mesa-dev
    check_error "6.4"
fi

if should_execute_step 6.5; then
    cd /home/nv/librealsense/build
    cmake ..
    check_error "6.5"
fi

if should_execute_step 6.6; then
    sudo make install -j8
    check_error "6.6"
fi

if should_execute_step 6.7; then
    cd /home/nv/librealsense
    sudo cp config/99-realsense-libusb.rules /etc/udev/rules.d/
    sudo udevadm control --reload-rules
    sudo udevadm trigger
    check_error "6.7"
fi

if should_execute_step 6.8; then
    pip install pyrealsense2
    sudo apt-get -y install ros-noetic-ddynamic-reconfigure
    check_error "6.8"
fi

if should_execute_step 6.9; then
    cp -rf /home/nv/20.04-vins-ego-swarm/realsense_ws /home/nv/
    cd /home/nv/realsense_ws
    source /opt/ros/noetic/setup.bash
    catkin_make
    check_error "6.9"
fi

# step 7: install opencv 4.6.0
if should_execute_step 7.1; then
    echo "Step 7: Installing OpenCV 4.6.0..."
    unzip /home/nv/20.04-vins-ego-swarm/其它依赖库/opencv-4.6.0.zip -d /home/nv/
    check_error "7.1"
fi

if should_execute_step 7.2; then
    unzip /home/nv/20.04-vins-ego-swarm/其它依赖库/opencv_contrib-4.6.0.zip -d /home/nv/
    check_error "7.2"
fi

if should_execute_step 7.3; then
    cd /home/nv/opencv-4.6.0/build
    sudo make install
    check_error "7.3"
fi

# step 8: install cv-bridge for ROS Noetic
if should_execute_step 8.1; then
    echo "Step 8: Installing cv-bridge for ROS Noetic..."
    cp -rf /home/nv/20.04-vins-ego-swarm/其它依赖库/catkin_pkg /home/nv/
    check_error "8.1"
fi

if should_execute_step 8.2; then
    cd /home/nv/catkin_pkg
    source /opt/ros/noetic/setup.bash
    catkin_make
    check_error "8.2"
fi

if should_execute_step 8.3; then
    echo "source /home/nv/catkin_pkg/devel/setup.bash" >> /home/nv/.bashrc
    check_error "8.3"
fi

# step 9: install ceres-solver and vins-fusion-gpu
if should_execute_step 9.1; then
    echo "Step 9: Installing ceres-solver and vins-fusion-gpu..."
    unzip /home/nv/20.04-vins-ego-swarm/其它依赖库/ceres-solver-1.14.0.zip -d /home/nv/
    check_error "9.1"
fi

if should_execute_step 9.2; then
    cd /home/nv/ceres-solver-1.14.0/build
    sudo apt-get -y install libgoogle-glog-dev libgflags-dev 
    check_error "9.2"
fi

if should_execute_step 9.3; then
    sudo apt-get -y install libatlas-base-dev 
    check_error "9.3"
fi

if should_execute_step 9.4; then
    sudo apt-get -y install libeigen3-dev
    check_error "9.4"
fi

if should_execute_step 9.5; then
    cmake ..
    check_error "9.5"
fi

if should_execute_step 9.6; then
    sudo make install -j8
    check_error "9.6"
fi

if should_execute_step 9.7; then
    cp -rf /home/nv/20.04-vins-ego-swarm/vins-fusion-gpu /home/nv/
    check_error "9.7"
fi

if should_execute_step 9.8; then
    cd /home/nv/vins-fusion-gpu
    source /opt/ros/noetic/setup.bash
    catkin_make
    check_error "9.8"
fi

# step 10: install ego-planner-swarm
if should_execute_step 10.1; then
    echo "Step 10: Installing ego-planner-swarm..."
    sudo apt-get -y install libarmadillo-dev systemd-timesyncd ros-noetic-multi-map-server ros-noetic-cv-bridge ros-noetic-cmake-modules
    check_error "10.1"
fi

if should_execute_step 10.2; then
    cp -rf /home/nv/20.04-vins-ego-swarm/ego-planner-swarm-ws /home/nv/
    check_error "10.2"
fi

if should_execute_step 10.3; then
    cd /home/nv/ego-planner-swarm-ws
    source /opt/ros/noetic/setup.bash
    catkin_make --pkg multi_map_server
    catkin_make -DCMAKE_BUILD_TYPE=Release 
    check_error "10.3"
fi

echo "All steps completed successfully!"
