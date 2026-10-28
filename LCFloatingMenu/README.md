# LCFloatingMenu for LiveContainer + SideStore

> Orbit Stage 1 now bundles the existing FloatingMenu module with a modular Core into the same standalone dylib. Existing `LCFloatingMenu.*` preferences and installation steps are preserved.


Standalone iOS 16+ arm64 tweak for classic single-task Guests and the opted-in LC host UI. Host injection also supports the optional fullscreen multitask switcher described below. Maintained on `lcss-original`.

## Features
- A slim draggable frosted-glass edge capsule, soft highlight and spring animations.
- Expandable translucent app switcher: return to LiveContainer, restart, switch to another LC guest.
- Built-in settings, DIY capsule shape, tint, size and opacity controls, haptic and confirmation toggles.
- Diagnostics: loading, overlay lifecycle, allowed/rejected switching, error categories. Share a `.json` file using the iOS share sheet; clear logs with confirmation. Size is limited to 256 KiB per file with a single rotated backup (approx. 512 KiB total).
- Per-app override of confirmation and collapsed opacity, saved in LCOrbit/config.json with legacy preference migration.
- Classic Guest switching restarts the LC guest process. The host's optional fullscreen multitask mode starts LC LiveProcess guests and switches existing tasks without terminating them.

## Download
- GitHub Actions: `Build LCFloatingMenu dylib` -> artifact `LCFloatingMenu-dylib`.
- No dedicated FloatingMenu Release is published. Use the workflow artifact or locally compiled `dist/LCFloatingMenu.dylib`.
- In-app update checking compares the embedded build commit against the public `lcss-original` branch; it detects source updates, not downloadable binaries.

## Install
1. In LC+SS -> Tweaks create a tweak folder named `LCFloatingMenu`.
2. Import `LCFloatingMenu.dylib` and use LC's Sign All Tweaks action.
3. In the desired Guest's settings select the `LCFloatingMenu` tweak folder.
4. Ensure that guest does not have the TweakLoader disabled; launch it in classic fullscreen mode.
5. Tap the orb for app switching; open Settings inside the panel for DIY controls.
6. Open 微珠设置 -> **诊断与日志** -> **微珠运行日志** or **Tweak 加载日志** to view, refresh, export, or clear the two separate log files.

## Two independent, in-app log viewers

In the floating menu, open **设置 -> 诊断与日志**:

- **微珠运行日志** (`LCOrbit/logs/runtime.json`): actual FloatingMenu and Orbit UI events, as before
- **Tweak 加载日志** (`LCOrbit/logs/tweaks.json`): read-only post-load audit of LC's correct global tweak root and the Guest's selected tweak folder; shows loaded, basename-match-only, not-observed, and disabled modules

Each viewer has **刷新 / 导出 / 清空**. The tweak log automatically records one snapshot shortly after the plugin starts and records another on each manual refresh. The menu log's Refresh only rereads the log. Clearing one does not affect the other.

Files are saved independently under the LC host Documents/LCOrbit/logs directory. Each current JSON file and its .old.json backup are bounded to 256 KiB. Export merges both into a single valid JSON document. Legacy plaintext logs are imported once without deleting the originals; clearing JSON history never imports them again. The plugin logs tweak paths/names, process context, configuration flags, status, and its own UI events; it does not capture App content.

**Shared Guest troubleshooting:** If LC host logs appear but no new snapshot appears after opening a shared Guest, that Guest may not have loaded this version of FloatingMenu. From the LC host open Tweak 加载日志 -> 刷新 and inspect `shared-disk`, `shared-global`, and `shared-app` lines. These lines inspect files on disk, not other processes; a missing dylib means it was not found at that path. `different-from-running-host` means the files differ byte-for-byte (signing may also change bytes), not necessarily that the Guest uses older code. To produce actual Guest-context snapshots, install the latest dylib into the shared Guest's **selected** tweak folder or shared global root, sign it appropriately, and relaunch the shared Guest.

**Scope:** This is an audit, not a decoder of NSLog or the Apple unified system log. not-observed means the image is not present in the current process and is not proof of a signing or dlopen error. TweakLoader's earlier Loaded tweak and Error lines cannot be recovered after the plugin starts. Capture them live in macOS Console, or modify TweakLoader itself to persist its errors. When this plugin fails to load, neither plugin log can record that failure.

## Manage shared global tweaks

In LiveContainer's **host UI** (not a Guest), open **微珠 -> 设置 -> 共享全局插件**. This is a separate settings-page entry, not part of diagnostics.

The manager shows ordinary global .dylib files found in the host's private `Documents/Tweaks` and in the shared `AppGroup/LiveContainer/Tweaks`, including shared-only files. Rows indicate private-source presence, whether the current host has loaded it, whether it is shared, and whether the files match. Not-loaded private dylibs remain visible but cannot be copied until loaded; the existing shared copy can still be revoked.

Tap individual rows to select them. The **top-right 操作 menu** provides **全选可共享插件**, **全选已共享插件**, **共享选中**, **取消共享选中**, **清空选择**, and **刷新插件列表**. Share/revoke actions require confirmation and report per-file results. TweakLoader.dylib is explicitly excluded. Other file types, symlinks, and per-app tweak folders are never modified.

Sharing copies only confirmed host-loaded private global dylibs, verifies copied contents, and backs up the former shared version before replacement. Revoking moves **only the shared copy** into `AppGroup/LiveContainer/LCFloatingMenu/TweakBackups` so it can be recovered. Private originals are never deleted. All changes are logged in `tweaks.log`; Guest processes already running must be relaunched. Copying preserves the dylib bytes but does not itself create a valid shared-Guest code signature.


## Developer host UI mode (no LC app changes)

LiveContainer already has a hidden developer setting: in LC Settings, tap the version label five times, then enable **Load Tweaks to LiveContainer Itself** (`LCLoadTweaksToSelf`). This loads tweaks from the **private** global `Documents/Tweaks` root when LC shows its own home UI. It does **not** change the separate shared-App-Group global tweak directory.

1. Put the host-compatible `LCFloatingMenu.dylib` in LC's top-level, **private** `Documents/Tweaks` folder, not only in a named per-Guest folder.
2. Use the Tweaks page's signature action to sign it with LC's certificate. The distributed build binary is not pre-signed.
3. Enable the developer toggle and fully quit/reopen LiveContainer so the host UI reloads the dylib.
4. In LC UI, open the orb -> settings -> 诊断与日志 to browse **微珠运行日志** and **Tweak 加载日志** independently. Menu diagnostics include `event=dylib-loaded detail=orbit-module context=lc-host` and `event=overlay-ready ... context=lc-host`.
5. The ordinary host UI omits **Return to LiveContainer** and **Restart Guest**. Enabling fullscreen multitasking adds **Return to LC** and **Close current task** controls.

**Warning:** The developer option loads **every eligible tweak in the private global Tweaks root** into the LC UI, not only FloatingMenu. An incompatible tweak can crash the LC host. Keep a copy of the original file, and if LC fails to start, remove the problematic dylib from LC's private Documents/Tweaks using the iOS Files interface before trying again.

The plugin's diagnostics file is in the LC host's `Documents/LCOrbit/logs/runtime.json`. The developer mode also logs an initialization notice to the Apple `NSLog` system console. **TweakLoader's own pre-load errors are still only in the system console**, not in the plugin diagnostic file. If the dylib never loads, the plugin cannot report its own loading failure.

## JSON 配置和日志（2026-10-28）

文件位于 iOS「文件」中 LC 目录下的 `LCOrbit`，即 `${LC_HOME_PATH}/Documents/LCOrbit`：

```text
LCOrbit/
  config.json
  config.last-good.json
  logs/
    runtime.json
    runtime.old.json
    tweaks.json
    tweaks.old.json
```

`config.json` 是插件配置来源，格式为：

```json
{
  "schemaVersion": 1,
  "preferences": {
    "LCFloatingMenu.fullscreenMultitask": true,
    "LCFloatingMenu.systemMultitaskMenu": true,
    "LCFloatingMenu.autoSyncSharedTweaks": false,
    "LCFloatingMenu.favoritePaths": ["private/Example.app"]
  }
}
```

首次自动迁移现有的 `LCFloatingMenu.*` 和 `LCOrbit.module.*` 偏好，包括收藏、排序、每 App 设置、外观和自动同步；旧偏好保留作为恢复来源。JSON 建立后删除其中一个键不会重新导入旧值。界面修改原子写入 JSON，手动编辑有效配置后回到 LC 前台或重启生效。模块开关的外部修改会执行完整启停生命周期，避免残留窗口或重复监听器。

格式错误、未知版本、不正确的值类型或超过 1 MiB 的配置不会覆盖上次有效值；原文件保留供修正，界面保存失败会提示。`config.last-good.json` 保存最近一次有效配置供恢复；多进程并发更新通过文件锁合并。

JSON 仅存放插件自身配置，不包含 LC 证书、系统多任务偏好或启动临时字段。按 App 分配插件仍使用 LC 原有 `LCAppInfo.plist → LCTweakFolder`，不改变加载协议。日志保持两类独立查看、导出、清空和轮转，JSON 记录时间、进程上下文、事件与详情；旧日志保留在原处，迁移仅导入每个旧文件最多 256 KiB 的尾部。

## 自动同步共享插件

在 **LC 主界面 → 微珠 → 设置 → 插件管理中心** 开启 **自动同步到共享插件**（默认关闭）。开启后立即同步；以后替换私有全局插件并重新打开 LC，或从后台回到 LC 时，自动检查和更新共享副本。从微珠启动 App 前也会等待本次自动同步完成。

只处理宿主已加载、符合现有共享条件的私有全局 `.dylib`，包括微珠自身；不处理 TweakLoader、符号链接或未加载文件。共享副本相同时不重复复制；替换旧版前备份并校验复制结果。已停用的共享副本保持停用。关闭开关停止后续自动同步，已共享的文件保留，仍可手动取消共享。

自动同步沿用原有文件共享和签名要求，不会热更新已运行的进程。更新本地插件后重启 LC 让宿主加载新版；已经运行的 Guest 也需要重启才能加载更新后的共享插件。同步结果写入 Tweak 加载日志。开关开启时，手动取消共享的文件可能在下次同步时重新共享；要长期保留停用状态，请停用共享副本或关闭自动同步。

## 微珠接管全屏多任务（仅更新插件）

前提是微珠已注入 **LC 宿主 UI**，LC 安装保留了 LiveProcess 扩展。保留原有独立的 **开启多任务** 开关；菜单选项不会再启停多任务。

恢复入口：在 LC 设置页长按「数据管理」，或在没有前台任务的 LC 主界面双指长按，打开完整微珠设置。恢复手势独立于悬浮菜单，因此系统模式隐藏微珠后仍可使用。不要关闭 LC 的宿主插件加载功能，否则插件本身无法运行。

- **系统模式**：使用 LC 原本的任务切换入口，隐藏微珠；窗口模式、最大化、缩放、窗口控制栏、安全区和同屏窗口行为均交给 LC。已启动任务继续保留，可从 LC 设置中的恢复手势切回微珠。
- **微珠菜单**：隐藏 LC Dock 显示，使用原有微珠全屏多任务菜单。LC 的 Dock 显示、边缘唤出和显隐命令会转交给微珠；从 LC 原应用列表以多任务方式启动 App，也会刷新微珠入口。
- 两种模式保留 LC 的任务和退出清理；只有微珠模式接管全屏布局。启用、切换、重启或关闭插件都不会改写 `LCMultitaskMode`。微珠全屏需要用户在 LC 多任务设置中选择虚拟窗口；原生窗口模式下会说明原因，不会替用户更改设置。
- 尚未设置菜单偏好的旧用户默认保留微珠。原有 `fullscreenMultitask` 偏好保留；错误版本中手动关掉的开关需要重新开启。
- 关闭「启用微珠」会隐藏悬浮层并恢复 LC 原有操作；保存多任务和菜单偏好，重新开启后恢复。设置入口独立于该模块，因此不会失去恢复入口。

也可进入 **微珠 → 设置 → 开启多任务 / 多任务切换菜单** 调整。

**只需在 LC 宿主启用微珠。** 子任务不用选择微珠插件目录，也不要求启用 Guest 的 TweakLoader。宿主全屏多任务启动资格不会因 Guest 禁用了插件加载器而被拒绝。即使共享全局目录导致 dylib 被映射进 LiveProcess，插件入口也会立即返回，不启动第二份 Core、微珠、日志审计或生命周期监听；普通经典单任务 Guest 保留原有插件行为。

- 微珠通过 LC 原有的 Objective-C 多任务启动接口启动 Guest，复用 LC 的容器、远程场景、键盘事件转发和退出清理；不修改 LC 源码或安装包。
- 微珠模式下 Guest 内容铺满宿主窗口并覆盖 LC 底部栏，隐藏标题栏、三个窗口按钮、边框、圆角和缩放手柄；系统模式恢复 LC 自身的窗口布局。微珠只隐藏原 Dock 的显示入口，保留 Dock 内部任务登记。
- A → B → A 切换复用同一容器的运行窗口，不主动结束其他任务。任务仍可能被系统回收；不保证无限后台驻留。
- **返回 LC** 隐藏任务窗口，保留进程；**关闭当前任务** 需确认并调用 LC 原有关闭流程。原 Guest 中的经典返回、重启和切换路径保留。
- 不再保存或回放 LC 原窗口模式快照。旧版 `previousMultitaskMode` 已停用，避免恢复过期值；若旧版曾覆盖你的 LC 设置，请在 LC 中重新选择一次，之后插件不会改写。切换到系统模式或关闭插件只恢复窗口装饰，不结束正在运行的任务。
- 只快捷启动已修补、已签名、容器明确且符合现有权限检查的普通 Guest。JIT、隐藏、锁定、签名待处理、容器被其他进程占用和需要经典兼容模式的 App 交给 LC 原入口处理；不自动绕过这些检查。SideStore 仍使用独立的经典启动路径。
- 启动过程中拒绝覆盖另一个待处理请求；失败和超时显示提示。宿主类或方法签名不兼容时拒绝启用接管。
- 创建任务窗口时，父控制器从 LC 任务承载视图的实际响应链取得。微珠提示框或设置窗口临时成为 key window 时，不会把任务挂到微珠的控制器下。

全屏几何在首次场景参数配置、AppScene 后续设置和实际远程场景更新三个边界校正。首次配置在 LC 创建或配置远程场景之前写入宿主尺寸、方向和安全区，覆盖新旧两套 hosting API；后续更新继续修正 LC 延迟 resize 和 iOS 18+ 深层安全区更新。仅处理当前初始化或已登记的受管理任务，不使用固定小窗口尺寸兜底。宿主几何无效时不发送无效覆盖值；远程内容视图建立后再应用布局。目标是修复顶部导航挤入状态栏或越出窗口，实际 App 渲染仍需真机确认。

这是运行时适配，已验证本仓库所对应接口的编译和自动化行为。真机上的远程场景显示、顶部内容位置、键盘焦点、状态栏、横竖屏安全区，以及关闭接管后的窗口恢复仍需验证。

## Limitations
- This tweak is not injected into SpringBoard and cannot overlay arbitrary separate installed iOS apps.
- Locked, hidden, JIT-required or 32-bit apps, or those with old patches, disabled signing or disabled TweakLoader, are excluded from quick switching; use LC's normal app list for those.
- **Warning:** Fast switching does not rerun the full LC signApp() path. When signing changes or an app is incompatible, return to LC and launch through the normal app list. Signing/launching cannot be guaranteed by the tweak.
- Diagnostics include bundle identifiers and predefined event categories, but do not intentionally log credentials, app content, certificates or signing keys.
- Icon display uses real LC-provided icon cache first, with CFBundleIcons and an unbranded placeholder as fallbacks.
- UIKit uses public `UIGlassEffect` dynamically where available and system blur on older iOS. An adaptive tint, edge stroke and a static gradient simulate the optical reference without continuously running GPU-intensive animations.
- Detailed settings use a dedicated opaque key `UIWindow` and restore the prior key window when closed. The LC host additionally receives a “微珠” navigation button on its settings home; it remains accessible independently of the floating module. Closing settings respects the selected menu and module visibility.
- GitHub Actions validates arm64 compilation, not runtime behavior. Import and sign with LC, then test on real hardware; a successful CI build does **not** guarantee that every guest is compatible.

## Gemini-design UI overhaul

- Edge microbead: default 12 x 38 pt, snap-to-edge, enlarged touch target, 3-second ultra-thin idle fade and long-press shortcuts.
- **Final drawer design:** Compact mode is one continuous ~108pt-wide Liquid Glass side drawer. Real Guest app icons (50pt) form a single centered vertical row, separated from a **fixed, vertical** action area by one fine hairline. Home, Settings, Collapse use matching 50pt glass icon tiles; Restart is optional. Only the app icon region scrolls. Standard mode uses the **same optical glass, cool edge highlight and matching tile rhythm** in a ~310pt-wide list, with app labels and a compact horizontal icon footer. Both retain a 75%-120% size control and screen bounds protection.
- Genuine LC app icons: first LCAppIconLight.png / LCAppIconDark.png in Guest bundle; fallback to CFBundleIcons assets or neutral icon (never fake initials).
- Settings center: preview, auto fade, haptics, DIY workshop, manager, per-App controls and diagnostics export.
- DIY workshop: Liquid / Minimal / Deep Crystal / Aurora themes, visual preview, opacity, bead size, color tint and icon theme controls.
- Menu management: favorite toggles and long-press drag handles to reorder app entries.
- Per-App override: explicit inheritance switch, collapsed opacity, double-tap-to-open and safe extra-thin edge display.
- Compatibility: UIKit dynamically creates UIGlassEffect when supported (iOS 26+); older versions use UIBlurEffect. Classic Guest launch remains available; the host can opt into fullscreen multitasking.
- Notes: source artwork is a visual reference, not a guarantee of pixel-identical rendering on all iOS releases.

## Independent categorized settings and built-in SideStore

- The app switcher fixes the Favorites header and icon-only footer in place; only the middle Guest app list scrolls. There is no standalone menu-management row or instructional subtitle in the switcher.
- The gear opens a separate full-screen **key** settings window, not another transparent floating sheet. A native grouped home organizes **Display & Appearance / Interaction & Switching / App Management / Diagnostics & Logs**. Each category has its own navigable detail page and returns to the Guest without relaunching.
- The built-in SideStore appears alongside ordinary LC Guest Apps when the LC+SS host contains a valid SideStoreApp.framework. The entry uses the LC internal SideStore launch flag, not a synthetic Guest bundle ID or external URL.
- SideStore switches close the current Guest and restart LC in classic single-task mode. If the built-in framework or LC launcher cannot be found, the entry fails closed with a diagnostic event.
- Action icons remain accessible through VoiceOver accessibility labels even though their visible text labels were removed.

## Native iOS 26 glass and settings refresh (2026-10-25)

- On iOS 26+, **every glass surface** is built from the public `UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular` and displayed in a `UIVisualEffectView`. The previous opaque color wash, custom gradient and manually stroked glowing rim have been removed from the native path. iOS 16-25 keeps a system `UIBlurEffect` accessibility/compatibility fallback only.
- The compact drawer is now **76pt wide before panel scaling** (instead of 108pt), with a single 50pt real App icon per row and matching action icon alignment. Hit areas remain 63pt high before scaling.
- Settings opens a **separate key UIWindow**. Appearance and Interaction controls now appear **inline on the first settings page**; App Management and Diagnostics remain push-navigation subpages.
- Favorites/Sorting now uses a native grouped system-color list with Auto Layout, proper dynamic label truncation, a star button and a drag handle; drop indices ignore the dragged row's own temporary transform.
- Keep LC+SS classic single-task launch logic and built-in SideStore one-shot launch safeguard. Real-device verification is still required even when arm64 compilation succeeds.


## 插件管理中心 2.0（宿主 UI）

路径：LC 主界面 → 微珠 → 设置 → 管理与支持 → **插件管理中心**。

- 右上角「操作」保留多选、批量共享、取消共享和刷新；列表右侧详情按钮可检查私有 / 共享副本的实际路径、大小、文件状态，单独启停、手动备份及恢复历史备份。
- 头部「按 App 分配插件」展示符合基本启动条件的私有与共享 Guest；点进 App 勾选插件并保存。
- 使用 LC 原生的 `LCAppInfo.plist → LCTweakFolder` 与 `TweakLoader` 递归加载。每个 App 拥有自己的 `Orbit-<digest>` 文件夹，放在该 App 所属的私有或共享 Tweaks 根目录；目标源码来源只能是普通 `.dylib` 文件，原始签名字节保留。
- **全局已启用的 dylib 始终会加载到同一作用域的其他 Guest**：按 App 分配并不构成排他隔离。要按 App 独享，应先在插件详情中停用对应全局副本（原名变成 `.dylib.disabled`），然后将它分配到目标 App。管理器保护私有根目录中的 `LCFloatingMenu.dylib` 和 `TweakLoader.dylib`，防止自我失联。
- 如果 App 已在 LC 原生设置中选择了非 Orbit 专属插件文件夹，不会强行覆盖。先在原设置取消选择再分配。
- 保存分配前备份 App 信息 `LCAppInfo.plist` 和原托管目录；批量创建临时目录、逐文件内容校验，再切换目录和配置。启停与恢复也有备份。备份保留在 private `Documents/LCFloatingMenu` 或共享 App Group `LiveContainer/LCFloatingMenu` 下。
- **写入后至少重启 Guest，建议先关闭再重开 LC 宿主，以免 LC UI 内存中的 App 配置写回覆盖磁盘修改**。这不是运行时卸载插件，也不会绕过签名或文件访问权限。初次发布仍需真机验证。

## LCOrbit modular runtime (Stage 1)

`LCFloatingMenu.dylib` is the existing distribution artifact, now compiled from the `LCOrbit/Core` framework and the FloatingMenu module. The original Guest switching and appearance logic is retained behind the module interface. Orbit is an **in-Guest runtime** and cannot display above SpringBoard or create a system-level Dynamic Island.

- `LCOrbitCore`: module registration, lifecycle notifications, and namespaced enabled flags.
- `LCOrbitHost`: LC/LC+SS selector adapter with supported-Guest checks.
- `LCOrbitOverlayManager`: a single non-key, pass-through `UIWindow` with a separate transparent layer per module.
- `LCOrbitEventBus`: main-thread, in-process events that modules can publish/subscribe to.
- `LCOrbitStorage`: namespaced configuration; original `LCFloatingMenu.*` keys are untouched.
- `LCFloatingMenu/LCFloatingMenu.m`: the first module and the familiar UI.

Local build (requires Xcode and the iPhoneOS SDK):

```sh
LCOrbit/Build/build.sh dist/LCFloatingMenu.dylib
```

**Future extension points:** implement `<LCOrbitModule>`, add its source to `Build/build.sh`, and register at Core bootstrap. A separate DynamicIsland module, signed binary add-ons, a module center, and real-device behavior testing are future work. Disabling the only currently installed FloatingMenu module is intentionally not exposed in the UI until the future module center is available. A third-party dylib is not sandboxed from the Guest, so untrusted modules should not be loaded.

## Orbit Stage 1 review fixes

- Fixed shared-window visible-notification re-entrancy, per-module appearance, and invalid geometry guards.
- Appearance monitoring now has cancellation and generation checks; Scene disconnect releases the module layer.
- Shared `LCOrbitGuestService` now owns Guest inventory and classic launch/SideStore bridging.
- Binary checks were extended. Real-device behavior and LC tweak signing still require verification.
