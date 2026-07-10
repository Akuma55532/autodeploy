#!/bin/bash

MODULE_NAME=cuda
MODULE_DEPS=""
MODULE_DESC="Install JetPack and CUDA environment"
MODULE_ASSET_DIR=${CUDA_ASSET_DIR:-${ASSET_DIR:-$HOME_DIR/uav_vision_pkg}}

check_cuda() {
    command -v nvcc >/dev/null 2>&1 &&
    [ -d /usr/local/cuda ]
}

install_cuda() {
    local home_dir=${HOME_DIR:-/home/nv}
    local bashrc_file="$home_dir/.bashrc"

    sudo tee /etc/apt/sources.list.d/nvidia-l4t-apt-source.list >/dev/null <<'EOF'
deb http://repo.download.nvidia.com/jetson/common r35.4 main
deb http://repo.download.nvidia.com/jetson/t234 r35.4 main
EOF

    sudo apt-get update
    sudo apt-get -y upgrade
    sudo apt-get -y install nvidia-jetpack python3-pip

    append_if_missing "" "$bashrc_file"
    append_if_missing "# CUDA environment variables" "$bashrc_file"
    append_if_missing "export LD_LIBRARY_PATH=/usr/local/cuda/lib64:\$LD_LIBRARY_PATH" "$bashrc_file"
    append_if_missing "export PATH=/usr/local/cuda/bin:\$PATH" "$bashrc_file"
    append_if_missing "export CUDA_HOME=/usr/local/cuda" "$bashrc_file"

    export LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}
    export PATH=/usr/local/cuda/bin:${PATH}
    export CUDA_HOME=/usr/local/cuda

    compgen -G "/usr/include/cudnn*" >/dev/null && sudo cp /usr/include/cudnn* /usr/local/cuda/include || true
    compgen -G "/usr/lib/aarch64-linux-gnu/libcudnn*" >/dev/null && sudo cp /usr/lib/aarch64-linux-gnu/libcudnn* /usr/local/cuda/lib64 || true

    nvcc -V
    sudo -H python3 -m pip install -U pip
    sudo -H python3 -m pip install jetson-stats
}
