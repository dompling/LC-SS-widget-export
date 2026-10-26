# LCMultitaskGuard (experimental)

Branch: `lcss-multitask-guard`, based on `lcss-original`.

## Scope

Diagnose LiveContainer multitask guest launch failures and unexpected LiveProcess exit while preserving the stable single-task path and the existing LCFloatingMenu tweak.

**This first implementation is host-side diagnostic instrumentation, not a standalone dylib.** A guest tweak is injected into the guest process and cannot reliably inspect the LC host's private Scene lifecycle. Once the actual failure point is known, we can evaluate an independent host-loaded dylib or keep a small source-level fix.

## Initial diagnostic checkpoints

- Guest launch and NSExtension discovery
- LiveProcess extension begin, cancellation, interruption and PID registration
- ProcessHandle availability and Scene presenter initialization
- Invalid / non-finite Scene frames and resize requests
- Guest termination and cleanup

Filter Xcode device console for `[LCMultitaskGuard]`.

## Test matrix

1. Launch one app in classic single-task mode (baseline).
2. Launch the same app in LC multitask mode.
3. Launch a second guest and return to the first.
4. Repeat with native multitask window mode enabled/disabled, where supported.
5. Collect LC logs, crash reports and device/iOS version; distinguish an app crash, extension termination and OS process kill.

## Constraints

- Do not suppress SIGTERM/SIGKILL or bypass iOS memory management.
- Do not falsely promise RAM state preservation after process death.
- Do not touch `lcss-original` or `LCFloatingMenu.dylib`.
- Do not enable automatic retry loops until the crash cause is understood.
- CI compilation is not proof of iPhone runtime compatibility.
