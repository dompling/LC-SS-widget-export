import Foundation

private var failures = 0
private var checks = 0
private func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !value() { failures += 1; print("FAIL \(message)") }
}

@main struct NativeWindowRegistryTests {
    static func main() {
        let registry = LCNativeTaskRegistry()
        let a = LCNativeTaskRecord(displayName: "A", dataUUID: "one", bundleId: "A.app", folder: "/private/A.app")
        let b = LCNativeTaskRecord(displayName: "B", dataUUID: "two", bundleId: "B.app", folder: "/private/B.app")
        expect(!a.isLaunchFailure, "pending launch does not display a terminated state")
        expect(registry.register(a) === a, "first task is registered")
        expect(registry.register(b) === b, "second task is independent")
        let duplicate = LCNativeTaskRecord(displayName: "A", dataUUID: "one", bundleId: "A.app", folder: "/private/A.app")
        expect(registry.register(duplicate) === a, "pending duplicate reuses original task")
        let wrongBundle = LCNativeTaskRecord(displayName: "B", dataUUID: "one", bundleId: "B.app", folder: "/private/B.app")
        expect(registry.register(wrongBundle) == nil, "container collision cannot replace a different app")
        let wrongFolder = LCNativeTaskRecord(displayName: "A", dataUUID: "one", bundleId: "A.app", folder: "/shared/A.app")
        expect(registry.register(wrongFolder) == nil, "namesake app in another folder cannot replace task")
        expect(registry.record(bundleId: "B.app", dataUUID: "one") == nil, "lookup checks both bundle and container")
        for (bundle, container) in [("../A.app", "three"), ("A.app", "../three"), ("A.app", ".."), ("A.app", "three/four"), ("A.app", "three\\four")] {
            let invalid = LCNativeTaskRecord(displayName: "invalid", dataUUID: container, bundleId: bundle, folder: "/private/A.app")
            expect(registry.register(invalid) == nil, "invalid path components cannot reach native launch")
        }

        var aResults: [Int] = [], bResults: [Int] = [], aRepeat: [Int] = []
        a.addCompletion { pid, error in aResults.append(pid.intValue); expect(error == nil, "A callback has its own success") }
        b.addCompletion { pid, error in bResults.append(pid.intValue); expect(error == nil, "B callback has its own success") }
        a.addCompletion { pid, _ in aRepeat.append(pid.intValue) }
        b.finish(pid: 22, error: nil)
        expect(aResults.isEmpty && bResults == [22], "out-of-order launch cannot steal A callback")
        a.finish(pid: 11, error: nil)
        expect(!a.isLaunchFailure, "valid initialized task keeps its content view")
        expect(aResults == [11] && aRepeat == [11] && bResults == [22], "every request receives its exact process PID")
        a.finish(pid: 99, error: NSError(domain: "late", code: 1))
        expect(aResults == [11] && a.pid == 11, "late completion cannot repeat or overwrite settled launch")
        var resumed = 0
        a.addCompletion { pid, _ in resumed = pid.intValue }
        expect(resumed == 11, "existing task immediately completes reuse request with original PID")
        expect(!registry.remove(duplicate), "stale token cannot remove registered task")
        expect(registry.record(bundleId: "A.app", dataUUID: "one") === a, "stale removal preserves real task")
        expect(registry.remove(a), "exact task can be removed")
        expect(registry.register(duplicate) === duplicate && a.token != duplicate.token, "reopened same identity gets a new stable token")
        expect(!registry.remove(a), "old task cannot remove reopened task")
        expect(registry.record(bundleId: "B.app", dataUUID: "two") === b, "closing one task leaves others intact")

        let failed = LCNativeTaskRecord(displayName: "C", dataUUID: "three", bundleId: "C.app", folder: "/private/C.app")
        var failedCalls = 0
        failed.addCompletion { pid, error in
            failedCalls += 1
            expect(pid.intValue == 0 && (error as NSError?)?.code == 7, "launch failure reaches own callback")
        }
        failed.finish(pid: 0, error: NSError(domain: "test", code: 7))
        expect(failed.isLaunchFailure, "initialization error selects the error/Close presentation")
        failed.finish(pid: 33, error: nil)
        expect(failedCalls == 1 && failed.pid == 0, "failed launch cannot later become a different task")
        print("Native window registry: \(checks - failures)/\(checks) passed")
        if failures > 0 { exit(1) }
    }
}
