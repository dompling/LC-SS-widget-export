# LCFloatingMenu for LiveContainer + SideStore

Standalone iOS 16+ arm64 tweak for classic, single-task fullscreen Guest Apps on the existing `lcss-original` branch.

## Features
- A slim draggable frosted-glass edge capsule, soft highlight and spring animations.
- Expandable translucent app switcher: return to LiveContainer, restart, switch to another LC guest.
- Built-in settings, DIY capsule shape, tint, size and opacity controls, haptic and confirmation toggles.
- Diagnostics: loading, overlay lifecycle, allowed/rejected switching, error categories. Share a `.log` file using the iOS share sheet; clear logs with confirmation. Size is limited to 256 KiB per file with a single rotated backup (approx. 512 KiB total).
- Per-app override of confirmation and collapsed opacity, saved using LC host preferences.
- Switching restarts the LC guest process; no multi-task windows and no preservation of live RAM state.

## Download
- GitHub Actions: `Build LCFloatingMenu dylib` -> artifact `LCFloatingMenu-dylib`.
- GitHub Releases: standalone prerelease tag `lc-floating-menu-<run number>`, file `LCFloatingMenu.dylib`.

## Install
1. In LC+SS -> Tweaks create a tweak folder named `LCFloatingMenu`.
2. Import `LCFloatingMenu.dylib` and use LC's Sign All Tweaks action.
3. In the desired Guest's settings select the `LCFloatingMenu` tweak folder.
4. Ensure that guest does not have the TweakLoader disabled; launch it in classic fullscreen mode.
5. Tap the orb for app switching; open Settings inside the panel for DIY controls.
6. When an App has problems, open `外观与菜单设置` -> `导出诊断日志` and share the `.log` file for analysis. You can choose `清空日志` to reset historical entries.

## Limitations
- This tweak is not injected into SpringBoard and cannot overlay arbitrary separate installed iOS apps.
- Locked, hidden, JIT-required or 32-bit apps, or those with old patches, disabled signing or disabled TweakLoader, are excluded from quick switching; use LC's normal app list for those.
- **Warning:** Fast switching does not rerun the full LC signApp() path. When signing changes or an app is incompatible, return to LC and launch through the normal app list. Signing/launching cannot be guaranteed by the tweak.
- Diagnostics include bundle identifiers and predefined event categories, but do not intentionally log credentials, app content, certificates or signing keys.
- Icons are colored monograms rather than private system-generated app icons.
- The look is an iOS Liquid Glass-inspired UIKit approximation, not the proprietary system material API.
- The settings screen is embedded in the guest overlay, not the LiveContainer host settings navigation.
- GitHub Actions validates arm64 compilation, not runtime behavior. Import and sign with LC, then test on real hardware; a successful CI build does **not** guarantee that every guest is compatible.
