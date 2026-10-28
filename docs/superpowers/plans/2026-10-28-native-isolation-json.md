# Native multitask isolation and JSON persistence

**Goal:** Preserve LC system multitask settings and all existing plugin behavior while making plugin preferences and logs durable JSON under the host Documents/LCOrbit directory.

**Authorization:** The user approved the reviewed fixes and migration, and requested three-dimensional review after implementation.

## Boundaries

- No LC host source changes, dependencies, Git metadata repairs, or automatic commits.
- System menu mode restores LC presentation and never forces full screen, scale, single-window visibility, or global window preferences.
- Bead mode retains full screen using LC virtual windows. Native backend settings remain user-owned; if native windows are selected, explain the required setting rather than changing it.
- Retire legacy previous-mode snapshots without writing stale values over current LC settings.
- Existing running task identity, exact-target close, background state, signing eligibility, SideStore behavior and plugin management remain protected.
- Plugin preferences only (LCFloatingMenu.* and LCOrbit.module.*) migrate to schema-versioned config.json; LC launch/session keys and LCAppInfo.plist contracts stay native.
- Valid external JSON reloads, invalid JSON preserves last-known-good values, atomic writes and process locks prevent corruption/lost updates; old preferences remain a recovery source.
- Runtime and audit JSON logs retain viewer/export/clear/rotation behavior, preserve legacy log history and avoid reimport after clear.

## Sequence

1. Save a pre-change file snapshot; write failing tests for system presentation isolation and startup preference preservation.
2. Fix native-mode boundaries and update UI wording; verify multitask suites.
3. Implement and test JSON preferences and structured logging independently, then route every plugin caller through them.
4. Run all regression suites, arm64 compilation, static analysis and binary verification.
5. Review three dimensions: behavior/regressions, persistence/data integrity, host/plugin boundary. Fix material findings and rerun affected tests.

## Evidence

- Baseline review build: 302 assertions across 12 behavior suites, arm64 build and smoke checks passed.
- Baseline bug reproduction: selecting system menu leaves LC mode=0; startup overwrites user-selected mode=1 back to 0; disable can restore stale mode=0.
- Pre-change snapshot: /tmp/LCOrbit-before-adjustment-20261028.tar.gz.

## Progress

- [x] Multitask isolation
- [x] JSON preferences
- [x] JSON logs
- [x] Integration and regression verification
- [x] Three-dimensional review

## Final verification

- 16 behavioral suites, 377 assertions, 0 failures; all source smoke checks passed.
- iOS 16+ arm64 dylib built and binary platform/architecture/install-name verification passed.
- clang static analyzer with Wall/Wextra: 17 translation units, 0 failures, 0 diagnostics.
- Independent three-dimensional review completed: functionality, JSON data integrity, native/plugin runtime isolation.
- Review findings fixed with observed failing-to-passing regression tests: external module lifecycle/rejected writes; native task identity during system switching; automatic-sync rejected saves; cross-process backup freshness; unsafe log-root symlinks. Additional unsafe-root fallback checks pass.
- Build evidence: /tmp/LCOrbit-adjusted-final-build.log. Analyzer evidence: /tmp/LCOrbit-final-analysis/.
- Deliverable: dist/LCFloatingMenu.dylib. Previous artifact retained at /tmp/LCFloatingMenu-before-json-20261028.dylib.
- Device-only gaps: LC signing/injection, native window animations, keyboard focus, rotation and real guest lifecycle cannot be established by Foundation tests or arm64 compilation.
