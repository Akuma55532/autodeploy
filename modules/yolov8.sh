#!/bin/bash

MODULE_NAME=yolov8
MODULE_DEPS="opencv"
MODULE_DESC="Install Ultralytics, Jetson PyTorch, and ONNX Runtime"
MODULE_ASSET_DIR=${YOLOV8_ASSET_DIR:-${ASSET_DIR:-$HOME_DIR/JetsonNXyolo}}

check_yolov8() {
    python3 -c 'import ultralytics, torch, torchvision, onnxruntime' >/dev/null 2>&1
}

install_yolov8() {
    local home_dir=${HOME_DIR:-/home/nv}
    local asset_dir=$MODULE_ASSET_DIR
    local yolo_zip=${YOLO_ZIP:-$asset_dir/yolo.zip}
    local yolo_dir=${YOLO_DIR:-$asset_dir/yolo}
    local torch_whl=${TORCH_WHL:-$yolo_dir/torch-2.2.0-cp38-cp38-linux_aarch64.whl}
    local torchvision_whl=${TORCHVISION_WHL:-$yolo_dir/torchvision-0.17.2+c1d70fe-cp38-cp38-linux_aarch64.whl}
    local onnxruntime_whl=${ONNXRUNTIME_WHL:-$yolo_dir/onnxruntime_gpu-1.17.0-cp38-cp38-linux_aarch64.whl}
    local opencv_dir=${OPENCV_DIR:-$home_dir/opencv-4.6.0}
    local jobs=${JOBS:-$(nproc)}

    sudo apt-get update
    sudo apt-get -y install libopenblas-dev libomp-dev python3-pip
    python3 -m pip install -U pip
    python3 -m pip install "ultralytics[export]"
    python3 -m pip uninstall -y torch torchvision opencv-python

    if [ "${REINSTALL_OPENCV_FOR_CSI:-1}" = "1" ]; then
        require_path "$opencv_dir/build"
        cd "$opencv_dir/build"
        sudo make install -j"$jobs"
    fi

    ensure_dir_from_zip "$yolo_dir" "$yolo_zip" "$asset_dir"
    require_path "$torch_whl"
    require_path "$torchvision_whl"
    require_path "$onnxruntime_whl"
    python3 -m pip install "$torch_whl" "$torchvision_whl" "$onnxruntime_whl"
    python3 -m pip install numpy==1.23.5 pyserial

    if [ -f "$yolo_dir/test_for_env.py" ]; then
        cd "$yolo_dir"
        python3 test_for_env.py
    fi
}
