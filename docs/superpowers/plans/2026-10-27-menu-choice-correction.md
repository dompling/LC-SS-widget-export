# Independent multitask menu and window correction

> **For agentic workers:** Execute inline with test-driven development and one independent final review. The user approved the requirements and explicitly requested implementation now.

**Goal:** Restore the previously accepted fullscreen multitask behavior, offer an independent LC/native versus bead menu choice, and provide a persistent LC settings entry while fixing scene geometry.

**Architecture:** Retain the original `fullscreenMultitask` engine preference and bridge; undo the last version's coupling between menu choice and engine enablement. A separate menu preference controls only Dock routing and bead visibility. Inject an entry into LC's settings navigation bar without editing SwiftUI host sources. Enforce geometry before scene creation as well as subsequent updates.

**Tech Stack:** Existing Objective-C/Foundation/UIKit runtime hooks, iPhoneOS arm64, macOS Foundation regression fixtures.

**Spec:** The user's confirmed six-point requirements immediately before “可以，开始做吧”.

## Global constraints

- No LC source edits, new dependencies, Git repair or commits.
- Existing Git worktree metadata points to a missing repository. No reliable historical checkout is available. Restore the prior accepted behavior from the existing engine and remove the later menu/engine coupling; preserve earlier containment and host-only fixes.
- Current files/artifact backed up to `/tmp/lcorbit-before-menu-correction-20261027/` before edits.
- Automatic plugin sync remains intact. LiveProcess does not bootstrap the plugin UI.
- Changing menus preserves all running tasks and fullscreen geometry. System choice hides bead only while multitasking is enabled. Disabling the plugin yields native LC behavior and leaves its settings entry reachable.

## Review focus

- Menu changes must not alter `LCMultitaskMode` or engine preference, kill tasks or restart LC.
- Settings must remain reachable when bead is hidden and the module is disabled; closing settings must respect visibility policy.
- LC native Dock switching must update the active task and avoid obsolete hidden views/state.
- Initial scene parameters must contain valid full bounds and safe areas before remote activation, on both hosting API paths.
- Runtime hooks must be scoped, ABI-checked, idempotent and pass through outside the LC host context.

### Task 1: Restore engine and separate menu preference

**Files:** `LCOrbit/Core/LCOrbitMultitask.{h,m}`, `LCOrbit/Core/LCOrbitMultitaskUI.m`, `LCFloatingMenu/LCFloatingMenu.m`, multitask/menu tests.

- [x] Add failing behavioral tests: both menus launch/reuse tasks; native choice does not disable engine; bead requests suppressed in system mode; overlay policy respects module/engine/menu state.
- [x] Implement independent persisted menu APIs; restore a separate engine switch; route Dock UI only by menu choice, retain common fullscreen layout.
- [x] Make LC native switching reconcile active task and hide other fullscreen views without process termination.
- [x] Run bridge/menu/guest regression targets.

### Task 2: Persistent entry in LC settings

**Files:** new `LCOrbit/Core/LCOrbitHostSettings.{h,m}`, `LCFloatingMenu/LCFloatingMenu.m`, build script and settings fixtures.

- [x] Add failing behavior tests for idempotent entry insertion, preserved native items and excluded unrelated bars. Module visibility/preferences tested in bridge; UIKit recovery presentation remains a device check.
- [x] Install guarded host navigation hook outside FloatingMenu module lifecycle; add “微珠” button on LC settings root.
- [x] Open settings using the tapped LC window's Scene even without overlay; provide plugin switch, engine switch and menu choice. Close according to visibility policy and restore host key window.
- [x] Verify iOS compilation and regression targets.

### Task 3: Initial and subsequent fullscreen geometry

**Files:** `LCOrbit/Core/LCOrbitMultitaskUI.m`, scene geometry fixtures.

- [x] Reproduce missing initial frame/orientation/insets before LC configures or creates remote scene using actual LC initialization block.
- [x] Scope scene-parameter hook to current managed presenter setup; apply host geometry last, restore scope with `@try/@finally`. Retain final remote updates and containment fix.
- [x] Test portrait, landscape, invalid transient geometry, unrelated scene pass-through, native-menu presentation and disabled mode.

### Task 4: Verify and deliver

**Files:** plugin/test READMEs, this plan, `dist/LCFloatingMenu.dylib`.

- [x] Run full build/regression/binary checks and static analysis; obtain independent review, fix material issues with tests.
- [x] Document settings path, menu semantics and device-only verification gaps; record artifact checksum.

## Ledger

- Baseline: existing bridge 36 assertions and scene geometry 12 assertions pass. Their coverage did not exercise independent menu state or first remote scene configuration.
- Prior baseline recovery: no reliable historical source checkout exists; behavioral restoration is explicit and backed by new regressions, not a claimed Git rollback.
- Task 1: independent menu behavior reproduced RED (missing independent API), then GREEN. Native Dock routing RED 2 failures then GREEN; native reorder RED 3 failures then GREEN; native minimize identity RED then GREEN. Bridge 48, menu 9 assertions pass.
- Task 2: entry insertion RED 3/9 then GREEN; absent root RED then GREEN. Full settings open no longer requires overlay. Entry installed at module registration, independently of the module's enable flag.
- Task 3: initial scene geometry RED 8/28 then GREEN 28/28, extracting LC's real setup blocks and both parameter paths. Existing parent/restore/ABI suites also pass.
- Final review: independent reviewer found two Important settings recovery issues (SwiftUI class-name assumption and first-foreground-scene selection); no Critical or Minor issues.
- Final fixes: replaced root-name matching with public UIKit tab containment and selected settings-tab ancestry; entry target weakly binds its originating window. Erased-root/two-foreground-scene tests RED 4/13 then GREEN 13/13, executing production open method. Detailed settings callback also retains the source Scene.
- Ruling: settings entry uses runtime UIKit navigation/tab containment from LC's current NavigationView/TabView, preserving native buttons and excluding task bars. Physical iOS SwiftUI containment and navigation presentation are still device checks; incompatible future UI internals may need adapter updates.
- Final review limitations: remote scene rendering, status bar/inset behavior, native Dock animation and actual key-window presentation cannot be established by macOS fixtures. Report these explicitly rather than treating test passes as device proof.
- Final verification: `sh LCOrbit/Build/build.sh` → 11 suites / 288 assertions / 0 failures, arm64 iPhoneOS 16+ build and binary smoke PASS. Clang static analysis with `-Wall -Wextra -Werror -Wno-unused-parameter` PASS for all four changed production implementation files. Both Important review findings fixed in one RED→GREEN pass; no deferred Minor findings.
- Artifact: `dist/LCFloatingMenu.dylib`, approximately 458 KiB, SHA-256 `aab0c7015b584eaac773d28d8f771fd19457ee3358a5bd4d7e3322b99f172e08`. Build log: `/tmp/lcorbit-menu-correction-final-build.log`.
