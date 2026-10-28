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

## Stage 1 stability follow-up

The OverlayManager now publishes its window reference before displaying the window, and installs the module layer before visibility notifications. Lifecycle dispatch includes foreground, background, deactivation, and Scene disconnect; the FloatingMenu module cancels stale appearance polls and tears down on disconnect. Module appearance is applied to the module layer, never to the shared window. Guest switching and SideStore one-shot launch behavior now reside behind `LCOrbitGuestService` for future modules.
