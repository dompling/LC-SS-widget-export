# 哔哩哔哩 LiveProcess 多任务全屏诊断测试包

本分支的 `LCFloatingMenu.dylib` 基于 1.0.6 构建，仅增加 **LiveProcess Guest 内的只读全屏请求探针**，没有把 PR #3 未验证的宿主方向修复混进来，也**不能保证直接修复全屏**。

## 测试步骤

1. 备份当前 `LCFloatingMenu.dylib`，把测试 dylib 放入 LC+SS 的 Tweaks 插件目录，使用 LC 原生管理界面重新签名，然后完全重启 LC/Guest。请勿直接替换已经运行的注入文件后期待热更新。
2. 确保哔哩哔哩是通过 LC **多任务 LiveProcess** 启动，且没有为该 App 关闭 TweakLoader 注入。重新打开哔哩哔哩，播放普通视频，点击原生全屏按钮两次。
3. 在微珠设置的 **诊断与日志 → 运行日志** 导出 JSON（如果无法导出，可在设备控制台筛选 `LCOrbit FullscreenProbe`）；只需要提供相关 `guest-fullscreen-*` 事件即可。
4. 再关闭 iOS 控制中心的竖排方向锁定，横持手机重试一次，记录行为有无变化。

## 如何解读

- `guest-fullscreen-probe-loaded`: 探针成功加载到 App 子进程，可看到 `geometryHook`/`orientationHook`/`presentationHook` 是否安装成功。
- `guest-fullscreen-geometry-request`: App 调用了 `UIWindowScene.requestGeometryUpdate...`，`orientationMask` 是它希望的方向。
- `guest-fullscreen-geometry-error`: 系统拒绝方向请求，`code`/`domain` 指明失败类型；探针会原样回调 App，不屏蔽错误。
- `guest-fullscreen-orientation-refresh`: App 请求重新评估控制器支持方向；`supportedMask` 能帮助辨别它是否仍处于仅竖屏状态。
- `guest-fullscreen-present`: App 尝试展示一个界面，通常可帮助判断全屏控制器是否被创建。**它不等于全屏成功。**
- **没有 `probe-loaded`**：说明本 dylib 没加载进 LiveProcess Guest，需要检查 TweakLoader、插件共享/专属注入以及设备日志，不能推断 App 没有请求全屏。
- 有 `probe-loaded` 但点击时以上事件均无变化：说明播放器可能使用了未覆盖的 UIKit/私有旋转路径，下一步应按真实设备日志针对性检查，不能继续盲目改宿主尺寸。

探针只记录 UIKit 类名、方向掩码、错误代码和状态，不记录视频内容、账号或网络请求。每次运行最多记录 120 条事件，仅用于短期排查。稳定正式版本请继续使用 v1.0.6。
