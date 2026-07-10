# AutoDeploy

面向 NVIDIA Jetson（JetPack r35.4 / Ubuntu 20.04）的模块化部署脚本。它按依赖顺序安装 ROS、CUDA、OpenCV、RealSense、YOLOv8、VINS-EGO、FAST-LIO 等组件，并记录已完成模块以便断点续跑。

## 使用前准备

- 在 Jetson 的 Bash 环境运行，不支持在 Windows 上直接部署。
- 将资料包完整解压到 `/home/nv`，不要更改资料包内文件或目录名称。
- 以具有 `sudo` 权限的用户运行；默认用户和目录可用 `HOME_DIR` 覆盖。

```bash
cd /path/to/autodeploy
chmod +x autodeploy.sh
./autodeploy.sh --validate
```

## 快速开始

先查看可用模块与 profile：

```bash
./autodeploy.sh --list
./autodeploy.sh --profile yolov8
```

确认执行计划后运行一个 profile：

```bash
./autodeploy.sh --profile yolov8 --run
```

## Profile

profile 会自动解析依赖，并为其中全部模块设置对应的 `ASSET_DIR`。

| Profile | 模块 | 默认资料包目录 |
| --- | --- | --- |
| `base` | ROS、CUDA | `$HOME_DIR/uav_vision_pkg` |
| `a8mini` / `c12` | ROS、CUDA、OpenCV、以太网驱动 | `$HOME_DIR/uav_vision_pkg` |
| `csi` | ROS、CUDA、OpenCV | `$HOME_DIR/uav_vision_pkg` |
| `realsense` | ROS、CUDA、OpenCV、RealSense | `$HOME_DIR/uav_vision_pkg` |
| `yolov8` | CUDA、OpenCV、YOLOv8 | `$HOME_DIR/JetsonNXyolo` |
| `vins_ego` | ROS、CUDA、OpenCV、RealSense、USB 权限、VINS-EGO | `$HOME_DIR/20.04-vins-ego-ros` |
| `fastlio_mid360s` | ROS、USB 权限、FAST-LIO MID-360 | `$HOME_DIR/20.04-fasterlio-ego-ros-mid360s` |

例如部署 FAST-LIO：

```bash
./autodeploy.sh --profile fastlio_mid360s --run
```

## 模块

| 模块 | 作用 | 依赖 |
| --- | --- | --- |
| `ros` | 通过 FishROS 安装 ROS1 | - |
| `cuda` | 安装 JetPack、CUDA 环境 | - |
| `opencv` | 编译 OpenCV 4.6.0（CUDA） | `cuda` |
| `realsense` | 安装 librealsense 与 Python 绑定 | `opencv` |
| `ethernet` | 安装 r8125 外置网卡驱动 | - |
| `yolov8` | 安装 Ultralytics、Jetson PyTorch、ONNX Runtime | `opencv` |
| `usb_permissions` | 安装 `70-ttyusb.rules` | - |
| `vins_ego` | 构建 VINS-EGO 相关 ROS 工作区与规划器 | `ros`、`realsense`、`usb_permissions` |
| `fastlio_mid360s` | 构建 Livox SDK2 与 FAST-LIO MID-360 | `ros`、`usb_permissions` |

也可以只运行指定模块，依赖会自动补齐：

```bash
ASSET_DIR=/home/nv/JetsonNXyolo ./autodeploy.sh --modules yolov8 --run
./autodeploy.sh --modules usb_permissions --run
```

## 常用命令

```bash
# 列出模块和 profile
./autodeploy.sh --list

# 查看执行计划（不安装）
./autodeploy.sh --profile realsense
./autodeploy.sh --modules cuda,opencv

# 校验模块、依赖和必需函数（不安装）
./autodeploy.sh --validate
./autodeploy.sh --validate --profile yolov8

# 运行 profile 或指定模块
./autodeploy.sh --profile vins_ego --run
./autodeploy.sh --modules ros,cuda --run

# 忽略已记录状态和检测结果，强制重跑整个计划
./autodeploy.sh --profile yolov8 --run --force
```

## 资料包与变量

安装前会检查当前模块的资料包目录；缺失时脚本会停止并提示正确解压位置。

- `ASSET_DIR`：覆盖当前命令的资料包目录；对 `--modules` 模式尤其有用。
- `HOME_DIR`：默认 `/home/nv`。
- 模块目录也可单独覆盖，例如 `YOLOV8_ASSET_DIR`、`FASTLIO_ASSET_DIR`、`VINS_EGO_ASSET_DIR`、`OPENCV_ASSET_DIR`。
- `REINSTALL_OPENCV_FOR_CSI=1`：YOLOv8 安装时重装 OpenCV；默认已启用。
- `JOBS`：编译并行度，默认 `nproc`。

## 状态与重跑

成功模块记录在 `state/installed.state`。再次运行会跳过已记录或检测已通过的模块。`--force` 会重跑执行计划中的所有模块，可能触发耗时编译和系统包更新，请谨慎使用。
