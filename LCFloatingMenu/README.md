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
- Icon display uses real LC-provided icon cache first, with CFBundleIcons and an unbranded placeholder as fallbacks.
- UIKit uses public `UIGlassEffect` dynamically where available and system blur on older iOS. An adaptive tint, edge stroke and a static gradient simulate the optical reference without continuously running GPU-intensive animations.
- Settings uses a dedicated, opaque, key `UIWindow` with `UINavigationController` and native inset-grouped category navigation; it does **not** create a separate native LC host settings tab, and restores the Guest key window when closed.
- GitHub Actions validates arm64 compilation, not runtime behavior. Import and sign with LC, then test on real hardware; a successful CI build does **not** guarantee that every guest is compatible.

## Gemini-design UI overhaul

- Edge microbead: default 12 x 38 pt, snap-to-edge, enlarged touch target, 3-second ultra-thin idle fade and long-press shortcuts.
- **Final drawer design:** Compact mode is one continuous ~108pt-wide Liquid Glass side drawer. Real Guest app icons (50pt) form a single centered vertical row, separated from a **fixed, vertical** action area by one fine hairline. Home, Settings, Collapse use matching 50pt glass icon tiles; Restart is optional. Only the app icon region scrolls. Standard mode uses the **same optical glass, cool edge highlight and matching tile rhythm** in a ~310pt-wide list, with app labels and a compact horizontal icon footer. Both retain a 75%-120% size control and screen bounds protection.
- Genuine LC app icons: first LCAppIconLight.png / LCAppIconDark.png in Guest bundle; fallback to CFBundleIcons assets or neutral icon (never fake initials).
- Settings center: preview, auto fade, haptics, DIY workshop, manager, per-App controls and diagnostics export.
- DIY workshop: Liquid / Minimal / Deep Crystal / Aurora themes, visual preview, opacity, bead size, color tint and icon theme controls.
- Menu management: favorite toggles and long-press drag handles to reorder app entries.
- Per-App override: explicit inheritance switch, collapsed opacity, double-tap-to-open and safe extra-thin edge display.
- Compatibility: UIKit dynamically creates UIGlassEffect when supported (iOS 26+); older versions use UIBlurEffect, and the launch path stays classic single-task.
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
