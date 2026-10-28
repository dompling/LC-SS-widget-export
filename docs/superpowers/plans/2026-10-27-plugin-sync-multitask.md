# Plugin sync and fullscreen multitasking implementation plan

> **For agentic workers:** Use test-driven execution and independent review. The user explicitly requested implementation of both features; no further design approval is pending.

**Goal:** Add opt-in automatic sharing of updated plugins and let the injected host menu launch/switch fullscreen multitask guests without changing LC source.

**Architecture:** Keep automatic sharing inside the existing validated file service. Add an Objective-C runtime adapter for LC's existing multitask launcher and decorated-window lifecycle. Keep task registration and cleanup while suppressing window decorations and Dock presentation in the opt-in fullscreen mode.

**Tech Stack:** Objective-C, Foundation/UIKit, Objective-C runtime, existing shell-driven macOS regression tests, arm64 iPhoneOS compilation.

**Spec:** User requests in this conversation and the accepted plugin-only implementation described immediately before them.

## Global constraints

- Only plugin source, tests, build script and documentation change; LC host source stays untouched.
- No new dependencies. Preserve signing/patch eligibility restrictions and special SideStore classic launch.
- Automatic sharing defaults off, persists, checks host context, skips disabled/invalid files, backs up and verifies replacements.
- Fullscreen multitask mode is host-only and user-controllable; classic guests retain the previous path.
- Do not invoke private Swift async ABI. Resolve Objective-C host classes/selectors dynamically and reject missing capabilities.
- Existing worktree Git metadata is broken; do not repair or commit it as part of this task.

## Review focus

- Updated private files must not override intentionally disabled shared copies.
- Repeated lifecycle notifications must not duplicate tasks or sharing work.
- Missing host API and launch errors must leave no stale selected-container state.
- Hidden tasks must remain alive; switching must reuse their container and not call terminate.
- Fullscreen bounds, content constraints, safe areas, status bar and rotation must remain coherent.

### Task 1: Automatic sharing

**Files:** `LCOrbit/Core/LCOrbitTweakSync.{h,m}`, `LCOrbit/Core/LCOrbitSharedTweaksViewController.m`, sync regression tests.

- [x] Write and run failing behavior tests for persistence, host-only enablement, first sharing, changed bytes, idempotence and disabled copies.
- [x] Implement `+automaticSyncEnabled`, `+setAutomaticSyncEnabled:`, `+syncAutomaticallyIfNeeded` with serialized existing share operations; add the settings switch.
- [x] Verify the existing file-management tests and new automatic-sync tests.

### Task 2: Plugin-only multitask bridge

**Files:** new `LCOrbit/Core/LCOrbitMultitask.{h,m}`, `LCOrbit/Core/LCOrbitGuestService.m`, `LCFloatingMenu/LCFloatingMenu.m`, `LCOrbit/Build/build.sh`, bridge tests.

- [x] Write and run failing behavior tests for host-only routing, current-task identity, existing-instance reuse, missing APIs and pending launch rejection.
- [x] Implement the runtime adapter: capability checks, container-indexed window registry, launch callback handling and fullscreen layout hooks. Keep host Dock task bookkeeping, suppress only its presentation.
- [x] Add persistent host UI toggle and distinguish home/hide, restart/terminate, classic switch and multitask switch semantics.
- [x] Invoke automatic sync at host startup/foreground and before guest launch; update build inputs and documentation.
- [x] Run every regression script, arm64 build and binary verification; independently review the final changes.

## Execution notes

- User authorization permits implementing the accepted approach now; no additional approval round is needed.
- Real-device behavior cannot be established by compilation or Foundation tests and must be reported separately.

## Review and verification ledger

- Initial five suites: 186 assertions, zero failures; arm64 iPhoneOS dylib build and binary smoke checks passed.
- Independent runtime review found three issues: stale compatibility cache, repeated toggle restoration, and native window geometry after disabling. First two reproduced RED then corrected: guest suite 63 and multitask suite 31 assertions green. Geometry regression verification is in progress.
- Ruling: defer restoring a saved native-window mode until existing virtual tasks close, so LC Dock registration/cleanup stays in virtual mode. Preserve the saved value across repeated toggles.
- Ruling: unknown/stale classic compatibility caches use LC original entry rather than guessing that LiveProcess is compatible.
- Ruling: an incompatible host API disables/rejects fullscreen mode; no classic restart fallback for a rejected multitask request.
- Geometry review finding reproduced with four failing assertions against production restore and LC geometry methods, then fixed by rebuilding LC's saved frame and rerunning its original scene activation path. All four now pass.
- Additional scope regression reproduced and fixed: same bundle/container in different filesystem scopes cannot be mistaken for or switch to the wrong running Guest.
- Final verification: six suites, 195 assertions, zero failures; arm64 iPhoneOS build and binary smoke checks passed. Clang static analysis with warnings treated as errors passed for all six modified production implementation files. Binary has no unresolved direct references to LC host classes.
- Final artifact: `dist/LCFloatingMenu.dylib`, approximately 435 KiB, SHA-256 `14faa5c84ab0ab9b129639cb655322e6a047974860d0e42c7ac70ad51dac892e`.
- Remaining verification: physical-device remote scene rendering, keyboard focus, rotation/safe areas, status-bar appearance, and on-device tweak signing. No claim of real-device validation is made.

## Follow-up: reported containment exception and host-only children

- User supplied `child view controller ... should have parent UIHostingController ... but requested UIViewController`, with stack through LC's decorated initializer and the plugin's `InitWindow`. This establishes a containment failure for that report, not a window-size assertion.
- Reproduced the parent mismatch against the actual production initializer hook: seven containment assertions, three failures before the fix. Resolve the parent from the existing task container's responder chain before calling LC's initializer; all seven assertions now pass. No LC source changes.
- User clarified that children must not need the plugin. Host multitask eligibility now ignores Guest loader flags while preserving all other launch restrictions. LiveProcess skips the plugin constructor before dispatch/module registration, independently of host preferences (LiveProcess uses a separate preference domain). Classic single-task Guests retain their runtime.
- Final follow-up verification: eight suites, 223 assertions, zero failures; arm64 dylib build and binary smoke checks passed. Three changed production implementations pass Clang static analysis with `-Wall -Wextra -Werror`.
- Updated artifact SHA-256: `fe3a5e76fda88330f109b17d7c6f2becdad4161096b75e7232ed236d84147e74`. Physical-device reproduction remains necessary to confirm the reported exception no longer occurs on the user's installation.

## Follow-up: geometry enforcement and explicit manager choice

- User clarified two visual issues (top App content outside bounds and LC multitask UI appearing) and requested an explicit LC/system versus bead setting, including a bridge for LC to invoke the plugin menu.
- Replaced the host fullscreen switch with a two-option segmented control, `系统（LC） / 微珠`, retaining the persisted preference. LC Dock startup/reveal/visibility commands now publish a host-only menu event in bead mode; task activation refreshes the floating entry. System mode invokes LC's original methods.
- Reproduced six geometry failures: delayed native resize could replace fullscreen dimensions/insets, and invalid host geometry could be forwarded. Added scoped final AppScene geometry enforcement and a post-presenter refresh.
- Independent review identified that iOS 18+ temporary settings do not establish remote safe areas. Added a final FBScene wrapper after LC's own UIKit wrapper, scoped to registered remote scenes. Executing LC's actual UIKit wrapper reproduced two further failures before the fix; remote geometry/insets now pass, and unmanaged remote scenes retain native behavior.
- Final validation: ten suites, 242 assertions, zero failures; complete arm64 iPhoneOS build and binary checks passed. Three changed production implementations pass Clang static analysis with warnings as errors.
- Updated artifact SHA-256: `3d9b029a48ab11bc0565f26a403b05300f371ea8b45ff02480aa78715193446d` (approximately 437 KiB). Device rendering/menu presentation is not established by the Foundation fixtures; initial system scene connection parameters are not guaranteed by these hooks.
