#!/bin/bash

MODULE_NAME=opencv
MODULE_DEPS="cuda"
MODULE_DESC="Install OpenCV with CUDA"

check_opencv() {
    pkg-config --modversion opencv4 2>/dev/null | grep -qx '4.6.0'
}

install_opencv() {
    local home_dir=${HOME_DIR:-/home/nv}
    local asset_dir=${ASSET_DIR:-$home_dir/uav_vision_pkg}
    local opencv_dir=${OPENCV_DIR:-$home_dir/opencv-4.6.0}
    local opencv_contrib_dir=${OPENCV_CONTRIB_DIR:-$home_dir/opencv_contrib-4.6.0}
    local opencv_zip=${OPENCV_ZIP:-$asset_dir/opencv-4.6.0.zip}
    local opencv_contrib_zip=${OPENCV_CONTRIB_ZIP:-$asset_dir/opencv_contrib-4.6.0.zip}
    local jobs=${JOBS:-$(nproc)}

    ensure_dir_from_zip "$opencv_dir" "$opencv_zip" "$home_dir"
    ensure_dir_from_zip "$opencv_contrib_dir" "$opencv_contrib_zip" "$home_dir"
    require_path "$opencv_dir"
    require_path "$opencv_contrib_dir"

    mkdir -p "$opencv_dir/build"
    cd "$opencv_dir/build"

    cmake -D CMAKE_BUILD_TYPE=RELEASE \
          -D CMAKE_INSTALL_PREFIX=/usr/local/ \
          -D OPENCV_EXTRA_MODULES_PATH="$opencv_contrib_dir/modules" \
          -D WITH_CUDA=ON \
          -D CUDA_ARCH_BIN=8.7 \
          -D CUDA_ARCH_PTX="" \
          -D ENABLE_FAST_MATH=ON \
          -D CUDA_FAST_MATH=ON \
          -D WITH_CUBLAS=ON \
          -D WITH_LIBV4L=ON \
          -D WITH_GSTREAMER=ON \
          -D WITH_GSTREAMER_0_10=OFF \
          -D WITH_QT=ON \
          -D WITH_OPENGL=ON \
          -D CUDA_NVCC_FLAGS="--expt-relaxed-constexpr" \
          -D WITH_TBB=ON \
          ..

    sudo make install -j"$jobs"
}
