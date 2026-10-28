# LCOrbit regression checks

`sh LCOrbit/Build/build.sh <output.dylib>` runs the behavioral suites before compiling, then verifies the arm64 iOS artifact. A failed test aborts the build. GitHub workflows may remain disabled; these checks run locally on macOS.

## Behavior contract

- Inventory and quick-launch eligibility are separate. Private, shared, JIT, manual-signing, outdated-patch, loader-disabled, hidden and locked guests remain visible for application management, favorites and sorting.
- Showing an entry does not unlock it or enable JIT. Launch actions must re-read current metadata and must not bypass authentication, JIT, patch or container checks. Do not clear LC's hidden or locked flags.
- Private and shared apps use distinct scope-aware identities, even when their folder names match. Never use a basename-only key for new favorites or sort order.
- The current guest remains visible and favoritable, but tapping its switcher entry must not restart it. The explicit Restart action is separate.
- Old basename-based preferences remain readable during migration.
- App-specific tweak assignment uses the complete installed inventory, not the quick-launch subset. Validate the target against the current installed path and preserve existing manually selected folders, source files and backups. Management remains restricted to the opted-in LC host UI.
- Preserve global sharing, batch revocation, enabled/disabled states, backup restoration and file details when changing app discovery. These operations must not rewrite unrelated app flags.
- Keep the compact management interface. Diagnostics belong in logs, not additional instruction banners.
- Automatic sharing is opt-in and host-only. It must preserve disabled copies, validate updates, keep backups and avoid duplicate writes across concurrent triggers.
- Host fullscreen multitasking must reuse existing windows, preserve other task processes and retain LC cleanup. Never silently restart the host when the requested multitask launch is rejected.

## Suites

- `sh LCOrbit/Tests/run-guest-tests.sh`: executes production scanning and menu selection against real temporary plists, including all app states, shared/private roots, container fallback, namesake collisions, original identity, stale selection and blocked launches.
- `sh LCOrbit/Tests/run-jit-favorites-tests.sh`: executes production `visibleApps`, `favorites` and `pinApp` methods. It verifies all-app visibility, actual preference persistence, independent same-name favorites, legacy preferences, removal and the existing four-item limit.
- `sh LCOrbit/Tests/run-tweak-center-tests.sh`: executes the production inventory, shared-file manager and assignment service. It loads only two no-op test dylibs from a temporary fixture and checks batch sharing/revocation, byte preservation, enabled/disabled states, current and legacy backups, restoration, file metadata and per-app assignments for JIT, manual-signing, hidden and locked apps.
- `sh LCOrbit/Tests/run-multitask-tests.sh`: executes the production host adapter against LC launch/presentation boundary doubles. Checks host-only mode, native preference isolation, failed JSON saves, extension and container ownership, launch arguments, duplicate-request rejection, async failure recovery, live-task reuse, return-home behavior, close-current isolation and preservation of user-owned LC settings across repeated toggles. Also checks independent menu choice, system-menu launch/reuse without fullscreen enforcement, overlay visibility, plugin-disable preference retention and native-minimize task identity.
- `sh LCOrbit/Tests/run-multitask-hook-tests.sh`: executes the production runtime signature guard against real Objective-C methods, rejecting incompatible return/argument ABIs before hook installation.
- `sh LCOrbit/Tests/run-multitask-restore-tests.sh`: executes the production restore path together with LC's real geometry methods. Checks normalized saved frame, restored remote-content dimensions and subsequent native scene updates, using small UIKit geometry/animation boundaries.
- `sh LCOrbit/Tests/run-multitask-parent-tests.sh`: executes the real initializer hook with LC containment boundaries. Reproduces the host/plugin key-window parent mismatch and verifies that the owning controller comes from the actual task container.
- `sh LCOrbit/Tests/run-bootstrap-tests.sh`: executes the production constructor body and verifies that LiveProcess never initializes another plugin runtime, even when host preferences are unavailable; ordinary classic Guests still initialize.
- `sh LCOrbit/Tests/run-multitask-scene-tests.sh`: executes production geometry enforcement against normal, delayed, invalid and rotated settings. Also runs LC's actual `hook_FBScene_performUpdateWithoutActivation` implementation to check that remote safe-area corrections happen after LC's derived insets, while unrelated scenes retain native behavior. Extracts LC’s actual initial settings/client blocks and both scene-parameter call paths, verifying full geometry at first configure/create consumption, scope restoration, exception unwinding and disabled/unmanaged pass-through.
- `sh LCOrbit/Tests/run-multitask-menu-tests.sh`: executes production Dock routing hooks. Bead mode forwards LC menu commands to the plugin; system mode preserves the three native entry points. The core suite separately verifies the host-only event bridge. Executes task view reordering and minimize hooks to verify current identity, task visibility and geometry when LC’s Swift Dock bypasses the bead activation path.
- `sh LCOrbit/Tests/run-host-settings-tests.sh`: executes the production settings-navbar recognition, entry update and opening methods. Verifies one entry, preserved native buttons, erased hosting roots with UIKit tab containment, title/context exclusions, absent roots and presentation in the tapped window when another scene is foreground. UIKit's actual modal rendering, SwiftUI navigation internals and physical-device recovery with module disabled remain device checks.
- `sh LCOrbit/Tests/verify.sh <output.dylib>`: binary and static smoke checks. These supplement the behavioral tests; they do not replace them.

The favorite suite can test an earlier checkout without changing the working tree:

```sh
ORBIT_SOURCE_ROOT=/path/to/old/source sh LCOrbit/Tests/run-jit-favorites-tests.sh
```

The previously shipped `b50cb10` fails the JIT/favorite assertions. The `b15793c` implementation fails the all-app and plugin-assignment assertions. UIKit rendering and actual iPhone launch/signing behavior still require device verification; a macOS fixture test does not claim to prove those.

## JSON and native-isolation checks

- `run-storage-tests.sh`: migration, namespace/type validation, external edits, durable writes, deletion semantics, last-good backup recovery, stale warm-process recovery after another process writes, unavailable roots, 20 threaded and 8 process writers, symlink and size guards.
- `run-json-log-tests.sh`: valid JSON export, Unicode/escaping, one-time legacy import, clear/rotation, concurrent process writers, corruption recovery and parent-root symlink refusal.
- `run-core-lifecycle-tests.sh`: external module start/stop transitions, disabled startup reactivation, idempotence and rejected-save behavior using production Core methods.
- `run-dock-visibility-tests.sh`: preserve original native hidden/touch state, suppress only bead-owned presentation and restore exactly once.

System/native LC backend preferences must never be written by plugin activation or recovery. System-mode task tracking may update identity for recovery gestures but must not change native geometry or other task visibility. Bead fullscreen remains opt-in and requires LC's virtual backend selected by the user.

## UIKit drawer regression app

Run `python3 LCOrbit/Tests/run-drawer-uikit-tests.py` on macOS with Xcode and an installed iOS Simulator runtime. The runner selects a booted available simulator, or boots an available iPhone if none is running. Use `--device NAME_OR_UDID` (or `ORBIT_SIMULATOR_DEVICE`) to select a device and `--output-dir PATH` to retain separate before/after evidence. `--source-root PATH` compiles another checkout while retaining this test harness.

The runner builds and signs a dedicated local fixture app, links the actual `LCFloatingMenu.m` and Core sources, installs only `local.orbit.DrawerRegression`, and executes the production menu on the simulator main thread. It resets only that fixture application's sandbox. It never launches or closes real guests: installed app inventory, current/running task state, task-close boundary and alert presentation are fixture methods. Task-close cases assert immediate execution without a confirmation alert and reject stale targets before the task boundary is invoked.

The JSON report and PNG snapshots are retained under `.omx/artifacts/drawer-uikit/` by default. Nonzero exit status means a failed assertion, build failure, missing simulator or a missing app report. Cases cover normal/compact 320/375pt host-height layout, normal close targets and compact upper-right badges with reachable icon centers at 75/100/120% scales, horizontal safe insets, header refresh/repetition, immediate list/footer closure and stale-target rejection, cancelled pan position/persistence, and removed round-orb/idle-fade behavior with legacy keys enabled.

These are **real UIKit simulator tests with synthetic host-window geometry and task fixtures**. They verify coordinate conversion, view layout, control routing and production action handling, but do not prove LC's actual SwiftUI tab-bar placement, physical sensor occlusion, remote scene integration or real task process termination. PNGs use UIKit layer rendering; they show synthetic layout, not hardware screenshots. The simulator suite remains an explicit check because some build machines have no iOS Simulator runtime.

Reduce Motion docking is reported separately as a production source contract: the docking method must consult `UIAccessibilityIsReduceMotionEnabled()`. This check does not claim to toggle the simulator accessibility C function or verify animation timing.
