# LCOrbit: modular LiveContainer Guest runtime

Stage 1 refactors the standalone `LCFloatingMenu.dylib` into a module plus a shared runtime without changing the user-facing tweak installation/signing workflow. The injected LC host can now optionally use LC's existing LiveProcess backend for fullscreen multitasking. This runtime does not extend SpringBoard or create system-level Live Activities.

## Layout

- `SDK/LCOrbitModule.h`: Objective-C protocol for first-party modules.
- `Core/LCOrbitCore.*`: central registry, lifecycle, persisted module enable flags.
- `Core/LCOrbitHost.*`: current Guest information and LC runtime bridge.
- `Core/LCOrbitGuestService.*`: validated Guest inventory, Guest launch, and SideStore classic one-shot launch.
- `Core/LCOrbitOverlayManager.*`: one shared transparent, non-key overlay window; each module gets a pass-through layer.
- `Core/LCOrbitEventBus.*`: in-process notifications for decoupled modules.
- `Core/LCOrbitStorage.*`: schema-versioned JSON preferences with legacy key migration, last-good recovery and process locks.
- `Core/LCOrbitLog.*`: structured bounded runtime/audit JSON logs and legacy history import.
- `Core/LCOrbitAutomaticPiP.m`: foreground preparation for per-App opt-in system PiP, with checked runtime interfaces and LC delegate-based content migration/restoration.
- `Build/build.sh`: build a sign-ready arm64 dylib compatible with existing LC tweak installation.
- `Tests/verify.sh`: static smoke checks for target platform, architecture, symbols and legacy launch/pref paths.

## First-party module checklist

1. Implement the `LCOrbitModule` protocol and choose a stable unique `moduleIdentifier`.
2. Add the `.m` files to the build, then register the module in Core bootstrap (later: dynamic discovery).
3. Acquire floating views with `context.overlays mountModule:inScene:` and observe events through `context.events`.
4. Remove the view and event observer tokens, stop any timers and clean up in `orbitWillStop`.
5. Use a unique storage prefix. Read LC state through `LCOrbitHost`, not private selectors scattered across new modules.
6. Validate the device's safe area, scene/window changes, light/dark theme, touch pass-through and Guest lifecycle.

## Operational guarantees and non-goals

- iOS 16+ arm64, with the previous native UIKit glass path on iOS 26+.
- Existing `LCFloatingMenu.*` preferences migrate to host `Documents/LCOrbit/config.json`; original preference keys and tweak folders remain compatible.
- Classic Guest and SideStore one-shot launch paths remain intact. Host bead mode uses LC virtual tasks; system mode preserves native LC settings and presentation.
- EventBus is in-process and cannot directly communicate with another Guest.
- Module enable state is persisted under `LCOrbit.module.<ID>.enabled`. Some injected behaviors require a Guest restart to fully unload.
- In Stage 1 modules are **compiled together**. Runtime download/install of third-party modules, isolation/sandboxing and a module-center GUI do not exist yet.
- Successful compilation does not verify actual device UI behavior. Test signing, orientation, foreground transitions and failure recovery on-device before replacing a known-good dylib.

## Adaptive task switching

In the bead settings, open **Behavior → Multitasking**, enable multitasking, then select **自适应**. Both iPhone and iPad can select **iPhone** for the staircase of LC task cards or **iPad** for the multiwindow layout. The iPad option uses system windows on compatible hosts and a live task grid inside single-window hosts.

- **iPhone presentation:** tap or pull the bead to open the task stack above the horizontal Dock. Earlier cards sit behind the focal card with tighter spacing and a slightly smaller scale. The cards keep their stacking order throughout horizontal scrolling. The Dock uses the drawer's ordered App icons and shows states as badges on the icons. Tap a preview to resume, flick it up to close the task, or tap the background to return to LC Home.
- **iPad presentation:** compatible hosts open native system windows that appear in the system app switcher. Single-window hosts show the running Apps in a grid with two columns in portrait and three in landscape. Swipe horizontally to browse more tasks.

The iPhone overview keeps each live controller, scene delegate and guest view in its original hierarchy. External root constraints are suspended during presentation, the original view geometry is saved, and guest input is disabled so the transparent overview window remains the sole gesture surface. A frosted system-material layer blurs the home beneath the switcher; each task card is an opaque, rounded App surface rather than a translucent overlay. Task order stays in first-launch order; the active task is selected at its original index. Closing a task keeps the switcher open with the remaining tasks, and the empty switcher stays open while its App dock can launch another task. Visibility, constraints, geometry, input and first responder are restored before resuming, closing, rotating or leaving the overview. PiP retains ownership of its surface. The UIKit fixture verifies this wiring with synthetic content; real LiveProcess remote-surface rendering still requires a signed-device check.

Reference: [Apple App Switcher](https://support.apple.com/guide/iphone/iph1a1f981ad/ios) and [upward close gesture](https://support.apple.com/en-us/109359). The iPhone overview remains an LC surface; the iPad path uses the actual system-managed windows.

Opening uses the existing inventory immediately and refreshes it off the UI thread. A scoped preference snapshot is shared with Core status queries only for the current event; writes remain validated, file-locked and fresh. The real 50-row status regression reduced 1,100 physical configuration loads to one. This removes a measured pre-animation workload, while device animation timing still requires on-device validation.

Build the plugin with `sh LCOrbit/Build/build.sh`. Check the host with `xcodebuild -project LiveContainer.xcodeproj -scheme LiveContainerSwiftUI -configuration Debug -sdk iphoneos CODE_SIGNING_ALLOWED=NO build`; unsigned build success does not establish device signing or installation.

Run `python3 LCOrbit/Tests/run-task-switcher-uikit-tests.py` for the UIKit overview fixture and `python3 LCOrbit/Tests/run-drawer-uikit-tests.py` for the existing drawer, including both adaptive entries. The fixture verifies live-view identity, transparent input layering and restoration using synthetic App content. `portrait-screen.png` is the simulator's whole-screen compositor output; fixture App content is synthetic. Real LiveProcess remote-surface rendering, iPad system-switcher snapshots and signed-device lifecycle behavior still need physical-device validation.

## Stage 1 stability follow-up

The OverlayManager now publishes its window reference before displaying the window, and installs the module layer before visibility notifications. Lifecycle dispatch includes foreground, background, deactivation, and Scene disconnect; the FloatingMenu module cancels stale appearance polls and tears down on disconnect. Module appearance is applied to the module layer, never to the shared window. Guest switching and SideStore one-shot launch behavior now reside behind `LCOrbitGuestService` for future modules.
