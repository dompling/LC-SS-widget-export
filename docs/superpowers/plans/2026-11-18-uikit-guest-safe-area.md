# Guest UIKit Safe-Area Experiment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give LC+SS microbead multitask an opt-in UIKit-safe-area mode that keeps Guest Scene full-sized while recovering lost top safe-area metrics.

**Architecture:** Keep the existing default full-window and legacy physical-avoidance policies untouched. Expose a third per-guest mode; the experiment derives an effective safe area from the host UIWindow's UIKit safe-area layout guide and visible status-bar metrics, sends these through existing FBScene initialization/finalization hooks, and never shifts the physical Guest window. Preserve PiP and unmanaged-scene bypass paths.

**Tech Stack:** Objective-C UIKit, existing LCOrbit runtime hooks, macOS clang fixture tests, GitHub Actions arm64 dylib build.

**Spec:** This plan is the standalone test-branch spec. Prior bug: per-guest physical-avoidance mode moves the Guest down by 59 pt and makes its Scene 59 pt shorter, clipping certain screens; default full-window mode leaves some Guest top controls overlapping the status bar.

## Global Constraints

- Base: `lcss-original`; branch: `feat/uikit-guest-safe-area`.
- Change only LCFloatingMenu and LCOrbit plugin/tests/CI, never core LiveContainer.
- Existing default and physical avoidance must keep their exact semantics for upgrades.
- UIKit experiment must be opt-in per app, full viewport, no additional vertical clipping.
- Avoid background callbacks on off-main UI, NaN frames and orientation regressions.
- No tag or GitHub Release.

## Review Focus

- Stale zero host top inset with valid safe-area guide should recover guide value.
- Temporarily zero host guide with visible status-bar should use its verified geometric height as fallback.
- Hidden status bar and legitimate zero-safe-area landscape must stay zero.
- Existing physical mode stays shrunk, default full-view stays unchanged.
- Unmanaged/PiP Guest scenes must never be rewritten.

---

### Task 1: Extend isolated fixture for three per-guest modes

**Files:** `LCOrbit/Tests/app_compatibility_tests.m`, `LCOrbit/Tests/run-app-compatibility-tests.sh`, `LCOrbit/Tests/multitask_scene_tests.m`, `LCOrbit/Tests/run-multitask-scene-tests.sh`.

**Interfaces:** `+topInsetModeForBundle:`, `+setTopInsetMode:forBundle:`, `HostUIKitSafeInsets(UIWindow *)`.

- [ ] Write tests: original physical remains mode 2, default mode 0, mode 1 uses full viewport while guide/statusbar rescue missing host top inset; bad key and arbitrary mode cannot affect other App.
- [ ] Run native regression fixture on GitHub macOS; verify failures for missing APIs.
- [ ] Implement minimal production code.
- [ ] Verify all scene and compatibility fixtures pass and commit.

### Task 2: Wire per-App selector and precise description

**Files:** `LCFloatingMenu/LCFloatingMenu.m`, `LCOrbit/Core/LCOrbitMultitask.h`.

- [ ] Update compatibility page to select Default, UIKit (experimental), Physical.
- [ ] Preserve the legacy switch storage semantics; distinguish physical mode so users know it shrinks the scene.
- [ ] Verify UI contracts and complete build.

### Task 3: Build test dylib on GitHub

**Files:** `.github/workflows/lc-floating-menu.yml`.

- [ ] Enable branch push-triggered Actions artifact upload; never publish a tag.
- [ ] Inspect macOS build and full native regression results.
- [ ] Deliver Actions artifact link with explicit note that visual Guest behavior needs a device test.
