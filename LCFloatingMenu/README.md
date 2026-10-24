# LCFloatingMenu for LiveContainer + SideStore

Standalone iOS 16+ arm64 tweak for classic, single-task fullscreen Guest Apps on the existing `lcss-original` branch.

## Features
- A slim draggable frosted-glass edge capsule, soft highlight and spring animations.
- Expandable translucent app switcher: return to LiveContainer, restart, switch to another LC guest.
- Built-in settings, DIY size and opacity controls, haptic and confirmation toggles.
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

## Limitations
- This tweak is not injected into SpringBoard and cannot overlay arbitrary separate installed iOS apps.
- Locked, hidden, JIT-required or 32-bit apps are excluded from fast switching; use LC's normal app list for those.
- Icons are colored monograms rather than private system-generated app icons.
- The look is an iOS Liquid Glass-inspired UIKit approximation, not the proprietary system material API.
- The settings screen is embedded in the guest overlay, not the LiveContainer host settings navigation.
- No device compatibility claims until a signed dylib has been tested on real hardware.
