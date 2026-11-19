//
//  MultitaskAppWindow.swift
//  LiveContainer
//
//  Created by s s on 2025/5/17.
//
import SwiftUI

// Native task identity and launch completion state.
// Foundation-only so the actual routing state can be exercised without a
// running extension or UIKit. UIKit session ownership stays below this block.
class LCNativeTaskRecord {
    let displayName: String
    let dataUUID: String
    let bundleId: String
    let folder: String
    let token = UUID().uuidString
    private(set) var pid: Int32 = 0
    private(set) var completed = false
    private var launchError: Error?
    private var completions: [(NSNumber, Error?) -> Void] = []
    var isLaunchFailure: Bool { completed && (launchError != nil || pid <= 0) }

    init(displayName: String, dataUUID: String, bundleId: String, folder: String) {
        self.displayName = displayName
        self.dataUUID = dataUUID
        self.bundleId = bundleId
        self.folder = URL(fileURLWithPath: folder).standardizedFileURL.resolvingSymlinksInPath().path
    }

    func addCompletion(_ completion: ((NSNumber, Error?) -> Void)?) {
        guard let completion else { return }
        if completed {
            completion(NSNumber(value: pid), launchError)
        } else {
            completions.append(completion)
        }
    }

    func finish(pid: Int32, error: Error?) {
        guard !completed else { return }
        completed = true
        self.pid = pid
        launchError = error
        let callbacks = completions
        completions.removeAll()
        for completion in callbacks { completion(NSNumber(value: pid), error) }
    }
}

final class LCNativeTaskRegistry {
    private(set) var records: [String: LCNativeTaskRecord] = [:]

    func record(bundleId: String, dataUUID: String) -> LCNativeTaskRecord? {
        guard let record = records[dataUUID], record.bundleId == bundleId else { return nil }
        return record
    }

    func register(_ candidate: LCNativeTaskRecord) -> LCNativeTaskRecord? {
        for component in [candidate.bundleId, candidate.dataUUID] {
            guard !component.isEmpty, component != ".", component != "..",
                  !component.contains("/"), !component.contains("\\") else { return nil }
        }
        if let existing = records[candidate.dataUUID] {
            guard existing.bundleId == candidate.bundleId, existing.folder == candidate.folder else { return nil }
            return existing
        }
        records[candidate.dataUUID] = candidate
        return candidate
    }

    @discardableResult func remove(_ record: LCNativeTaskRecord) -> Bool {
        guard records[record.dataUUID] === record else { return false }
        records.removeValue(forKey: record.dataUUID)
        return true
    }
}
// End native task registry.

@available(iOS 16.1, *)
final class MultitaskAppInfo: LCNativeTaskRecord {
    weak var scene: UIWindowScene?
    weak var controller: AppSceneViewController?
    var sessionIdentifier: String?
    var closing = false
    var adaptive = false
}

@available(iOS 16.1, *)
private struct NativeTaskSceneReader: UIViewRepresentable {
    let task: MultitaskAppInfo

    final class Reader: UIView {
        var task: MultitaskAppInfo?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let scene = window?.windowScene, let task else { return }
            task.scene = scene
            task.sessionIdentifier = scene.session.persistentIdentifier
            var userInfo = scene.session.userInfo ?? [:]
            userInfo["LCNativeTaskToken"] = task.token
            scene.session.userInfo = userInfo
            scene.title = task.displayName
            (scene.statusBarManager as? LCStatusBarManager)?.nativeWindowViewController = task.controller
        }
    }

    func makeUIView(context: Context) -> Reader {
        let view = Reader()
        view.isUserInteractionEnabled = false
        view.task = task
        return view
    }
    func updateUIView(_ uiView: Reader, context: Context) { uiView.task = task }
}

@available(iOS 16.1, *)
@objc class MultitaskWindowManager: NSObject {
    @Environment(\.openWindow) static var openWindow
    private static let registry = LCNativeTaskRegistry()
    // WindowGroup values are generation tokens, not reusable container IDs.
    // A terminated window can never capture a later launch of the same App.
    static var appDict: [String: MultitaskAppInfo] {
        Dictionary(uniqueKeysWithValues: registry.records.values.compactMap { record in
            (record as? MultitaskAppInfo).map { ($0.token, $0) }
        })
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "LCNativeTaskWindow", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    @objc(orbitSupportsNativeTaskWindows)
    class func orbitSupportsNativeTaskWindows() -> Bool {
        UIApplication.shared.supportsMultipleScenes
    }

    @objc(orbitOpenAppWindowWithDisplayName:bundleId:dataUUID:completionHandler:)
    class func orbitOpenAppWindow(displayName: String, bundleId: String, dataUUID: String,
                                 completionHandler: ((NSNumber, Error?) -> Void)?) {
        openNativeWindow(displayName: displayName, bundleId: bundleId, dataUUID: dataUUID,
                         adaptive: true, completion: completionHandler)
    }

    @objc class func openAppWindow(displayName: String, dataUUID: String, bundleId: String, pidCallback: ((NSNumber, Error?) -> Void)?) {
        openNativeWindow(displayName: displayName, bundleId: bundleId, dataUUID: dataUUID,
                         adaptive: false, completion: pidCallback)
    }

    private static func openNativeWindow(displayName: String, bundleId: String, dataUUID: String,
                                         adaptive: Bool, completion: ((NSNumber, Error?) -> Void)?) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                openNativeWindow(displayName: displayName, bundleId: bundleId, dataUUID: dataUUID,
                                 adaptive: adaptive, completion: completion)
            }
            return
        }
        guard orbitSupportsNativeTaskWindows() else {
            completion?(0, failure("当前设备不支持系统多窗口。"))
            return
        }
        var shared = false
        guard !bundleId.isEmpty, !dataUUID.isEmpty,
              let folder = LCSharedUtils.findBundle(withBundleId: bundleId, isSharedAppOut: &shared)?.bundlePath,
              LCUtils.liveProcessBundleIdentifier() != nil else {
            completion?(0, failure("无法找到目标 App 或 LiveProcess 扩展。"))
            return
        }
        let candidate = MultitaskAppInfo(displayName: displayName, dataUUID: dataUUID, bundleId: bundleId, folder: folder)
        candidate.adaptive = adaptive
        guard let task = registry.register(candidate) as? MultitaskAppInfo else {
            completion?(0, failure("该容器已被其他 App 或作用域的任务占用。"))
            return
        }
        guard !task.closing else {
            completion?(0, failure("目标窗口正在关闭，请稍后重试。"))
            return
        }
        // A finished process may not have delivered its disconnect callback yet.
        if task !== candidate, task.completed, task.controller?.isAppRunning != true {
            removeTask(task, terminate: true)
            openNativeWindow(displayName: displayName, bundleId: bundleId, dataUUID: dataUUID,
                             adaptive: adaptive, completion: completion)
            return
        }
        task.addCompletion(completion)
        if task !== candidate {
            if task.scene != nil { _ = activate(task) }
            return
        }
        DataManager.shared.model.enableMultipleWindow = true
        openWindow(id: "appView", value: task.token)
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            guard registry.record(bundleId: bundleId, dataUUID: dataUUID) === task, !task.completed else { return }
            task.finish(pid: 0, error: failure("系统窗口启动超时，请重试。"))
            removeTask(task, terminate: true)
            if let session = task.scene?.session {
                UIApplication.shared.requestSceneSessionDestruction(session, options: nil)
            }
        }
    }

    private static func descriptor(_ task: MultitaskAppInfo) -> NSDictionary {
        let running = !task.closing && task.controller?.isAppRunning == true
        return ["bundle": task.bundleId, "container": task.dataUUID, "folder": task.folder,
                "title": task.displayName, "token": task.token, "running": running,
                "sceneIdentifier": task.sessionIdentifier ?? "",
                "active": running && task.scene?.activationState == .foregroundActive]
    }

    @objc(orbitShowHome)
    class func orbitShowHome() -> Bool {
        guard Thread.isMainThread, orbitSupportsNativeTaskWindows() else { return false }
        let taskSessions = Set(appDict.values.compactMap(\.sessionIdentifier))
        if let home = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: {
            $0.session.role == .windowApplication && $0.session.userInfo?["LCNativeTaskToken"] == nil &&
                !taskSessions.contains($0.session.persistentIdentifier)
        }) {
            UIApplication.shared.requestSceneSessionActivation(home.session, userActivity: nil, options: nil) { error in
                NSLog("Native home activation failed: %@", error.localizedDescription)
            }
        } else {
            openWindow(id: "Main")
        }
        return true
    }

    @objc(orbitRunningTasks)
    class func orbitRunningTasks() -> [NSDictionary] {
        guard Thread.isMainThread else { return [] }
        return appDict.values.filter { !$0.closing && $0.controller?.isAppRunning == true }.map(descriptor)
    }

    @objc(orbitTaskForBundleId:dataUUID:)
    class func orbitTask(bundleId: String, dataUUID: String) -> NSDictionary? {
        guard Thread.isMainThread, let task = registry.record(bundleId: bundleId, dataUUID: dataUUID) as? MultitaskAppInfo else { return nil }
        return descriptor(task)
    }

    private static func activate(_ task: MultitaskAppInfo) -> Bool {
        guard !task.closing, let scene = task.scene else { return false }
        UIApplication.shared.requestSceneSessionActivation(scene.session, userActivity: nil, options: nil) { error in
            NSLog("Native task activation failed: %@", error.localizedDescription)
        }
        return true
    }

    @objc(orbitActivateTaskWithBundleId:dataUUID:)
    class func orbitActivateTask(bundleId: String, dataUUID: String) -> Bool {
        guard Thread.isMainThread,
              let task = registry.record(bundleId: bundleId, dataUUID: dataUUID) as? MultitaskAppInfo,
              task.controller?.isAppRunning == true else { return false }
        return activate(task)
    }

    @objc(orbitCloseTaskWithBundleId:dataUUID:)
    class func orbitCloseTask(bundleId: String, dataUUID: String) -> Bool {
        guard Thread.isMainThread,
              let task = registry.record(bundleId: bundleId, dataUUID: dataUUID) as? MultitaskAppInfo,
              !task.closing, task.controller?.isAppRunning == true, let session = task.scene?.session else { return false }
        task.closing = true
        // Termination follows the actual disconnect, so a rejected system close
        // request cannot destroy a still-visible task.
        UIApplication.shared.requestSceneSessionDestruction(session, options: nil) { error in
            task.closing = false
            NSLog("Native task close failed: %@", error.localizedDescription)
        }
        return true
    }

    static func taskDidExit(_ task: MultitaskAppInfo) {
        removeTask(task, terminate: false)
    }

    static func disconnect(_ task: MultitaskAppInfo) {
        removeTask(task, terminate: true)
    }

    static func discardSessions(_ sessions: Set<UISceneSession>) {
        let identifiers = Set(sessions.map(\.persistentIdentifier))
        for task in appDict.values where task.sessionIdentifier.map({ identifiers.contains($0) }) == true {
            removeTask(task, terminate: true)
        }
    }

    private static func removeTask(_ task: MultitaskAppInfo, terminate: Bool) {
        guard registry.remove(task) else { return }
        if terminate { task.controller?.terminate() }
        MultitaskDockManager.shared.removeRunningApp(task.dataUUID)
        task.finish(pid: 0, error: failure("任务窗口已关闭。"))
    }
    @objc class func openExistingAppWindow(dataUUID: String) -> Bool {
        guard Thread.isMainThread,
              let task = registry.records[dataUUID] as? MultitaskAppInfo,
              !task.closing else { return false }
        if task.controller?.isAppRunning == true { return activate(task) }
        return !task.completed
    }
}

@available(iOS 16.1, *)
struct AppSceneViewSwiftUI: UIViewControllerRepresentable {
    @Binding var show: Bool
    let task: MultitaskAppInfo
    let onAppInitialize: (Int32, Error?) -> Void
    
    class Coordinator: NSObject, AppSceneViewControllerDelegate {
        let task: MultitaskAppInfo
        let onExit: () -> Void
        let onAppInitialize: (Int32, Error?) -> Void
        init(task: MultitaskAppInfo, onAppInitialize: @escaping (Int32, Error?) -> Void, onExit: @escaping () -> Void) {
            self.task = task
            self.onAppInitialize = onAppInitialize
            self.onExit = onExit
        }
        
        func appSceneVCAppDidExit(_: AppSceneViewController!) {
            onExit()
        }
        
        func appSceneVC(_ vc: AppSceneViewController!, didInitializeWithError error: (any Error)!) {
            DispatchQueue.main.async {
                if let vc {
                    (vc.view.window?.windowScene?.statusBarManager as? LCStatusBarManager)?.nativeWindowViewController = vc
                }
            }
            onAppInitialize(vc?.pid ?? 0, error)
        }
        
        func appSceneVCWillActivateScene(_ vc: AppSceneViewController!) {
            vc.updateSettings { settings in
                guard let settings else { return }
                let defaultInsets = vc.view.window?.safeAreaInsets ?? .zero
                settings.peripheryInsets = defaultInsets
                settings.safeAreaInsetsPortrait = defaultInsets
                settings.deviceOrientation = UIDevice.current.orientation
                settings.setInterfaceOrientation(vc.view.window?.windowScene?.interfaceOrientation ?? .portrait)
                if(settings.interfaceOrientation().isLandscape) {
                    settings.setFrame(CGRect(x: 0, y: 0, width: vc.view.frame.size.height, height: vc.view.frame.size.width))
                } else {
                    settings.setFrame(CGRect(x: 0, y: 0, width: vc.view.frame.size.width, height: vc.view.frame.size.height))
                }
            }
            // fix live resize
            vc.contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
        
        func appSceneVC(_ vc: AppSceneViewController!, didUpdateFrom settings: UIMutableApplicationSceneSettings!, transitionContext context: Any!, lifecycleActionType actionType: UInt32) {
            settings.interruptionPolicy = 0
            //settings.peripheryInsets = vc.view.window?.safeAreaInsets ?? .zero
            vc.presenter.scene.updateSettings(settings, withTransitionContext: context, completion: nil)
            // Not sure what actionType 2 is, but it's only set when this scene enters foreground, so we can pass URL scheme here
            if actionType == 2, let launchUrl = UserDefaults.standard.string(forKey: "launchAppUrlScheme") {
                UserDefaults.standard.removeObject(forKey: "launchAppUrlScheme")
                vc.openURLScheme(launchUrl)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(task: task, onAppInitialize: onAppInitialize, onExit: {
            DispatchQueue.main.async {
                MultitaskWindowManager.taskDidExit(task)
                show = false
            }
        })
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        guard MultitaskWindowManager.appDict[task.token] === task,
              let controller = AppSceneViewController(bundleId: task.bundleId, dataUUID: task.dataUUID,
                                                       delegate: context.coordinator, nativeWindow: true) else {
            return UIViewController()
        }
        task.controller = controller
        return controller
    }
    
    func updateUIViewController(_ vc: UIViewController, context _: Context) {
        if let vc = vc as? AppSceneViewController {
            if !show {
                vc.terminate()
            }
        }
    }

    static func dismantleUIViewController(_ vc: UIViewController, coordinator: Coordinator) {
        // UIKit may release the view before didDisconnect reaches SwiftUI.
        // Stop this exact controller while it is still strongly available.
        (vc as? AppSceneViewController)?.terminate()
        MultitaskWindowManager.disconnect(coordinator.task)
    }
}

@available(iOS 16.1, *)
struct MultitaskAppWindow: View {
    @State var show = true
    @State var pid = 0
    @State var appInfo: MultitaskAppInfo? = nil
    @State var errorMessage: String? = nil
    @State private var hasScheduledAutoClose = false
    @State private var didRequestManualClose = false
    @EnvironmentObject var sceneDelegate: SceneDelegate
    @Environment(\.openWindow) var openWindow
    @AppStorage("LCMultitaskMode", store: LCUtils.appGroupUserDefault) var multitaskMode: MultitaskMode = .virtualWindow
    @AppStorage("LCSkipTerminatedScreen", store: LCUtils.appGroupUserDefault) var skipTerminatedScreen = false
    let pub = NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)
    init(id: String) {
        guard let appInfo = MultitaskWindowManager.appDict[id] else {
            return
        }
        _appInfo = State(initialValue: appInfo)
    }
    
    var body: some View {
        let isVirtualWindowMode = multitaskMode == .virtualWindow && appInfo?.adaptive != true
        if show, let appInfo, !appInfo.isLaunchFailure {
            GeometryReader { _ in
                AppSceneViewSwiftUI(show: $show, task: appInfo,
                                    onAppInitialize: { pid, error in
                    DispatchQueue.main.async {
                        if error == nil {
                            self.pid = Int(pid)
                        } else {
                            self.errorMessage = error?.localizedDescription
                        }
                        appInfo.finish(pid: pid, error: error)
                        if error != nil {
                            show = false
                            MultitaskWindowManager.disconnect(appInfo)
                        }
                    }
                })
                .background(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea(.all, edges: .all)
            .background(NativeTaskSceneReader(task: appInfo))
            .navigationTitle(Text(appInfo.displayName))
            .onReceive(pub) { out in
                if let scene1 = appInfo.scene, let scene2 = out.object as? UIWindowScene, scene1 == scene2 {
                    MultitaskWindowManager.disconnect(appInfo)
                    show = false
                }
            }
            
        } else if skipTerminatedScreen && isVirtualWindowMode, appInfo != nil {
            Color.clear
                .ignoresSafeArea(.all, edges: .all)
                .onAppear {
                    guard !didRequestManualClose else { return }
                    if let appInfo {
                        MultitaskRelaunchManager.scheduleRelaunchIfNeeded(bundleId: appInfo.bundleId, dataUUID: appInfo.dataUUID, isManualTermination: false)
                    }
                    if !hasScheduledAutoClose {
                        hasScheduledAutoClose = true
                        DispatchQueue.main.async {
                            requestSceneDestruction(isManual: false)
                        }
                    }
                }
        } else {
            VStack {
                Text("lc.multitaskAppWindow.appTerminated".loc)
                    .font(.largeTitle)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(.body, design: .monospaced))
                    Button("lc.common.copy".loc) {
                        UIPasteboard.general.string = errorMessage
                        requestSceneDestruction(isManual: true)
                    }
                    .buttonStyle(.bordered)
                }
                Button("lc.common.close".loc) {
                    requestSceneDestruction(isManual: true)
                }
                .buttonStyle(.bordered)
            }.onAppear {
                // appInfo == nil indicates this is the first scene opened in this launch. We don't want this so we open lc's main scene and close this view
                // however lc's main view may already be starting in another scene so we wait a bit before opening the main view
                // also we have to keep the view open for a little bit otherwise lc will be killed by iOS
                if appInfo == nil {
                    if DataManager.shared.model.mainWindowOpened {
                        requestSceneDestruction()
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            if !DataManager.shared.model.mainWindowOpened {
                                openWindow(id: "Main")
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                requestSceneDestruction()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func requestSceneDestruction(isManual: Bool = false) {
        if isManual {
            didRequestManualClose = true
        }
        guard let session = appInfo?.scene?.session ?? sceneDelegate.window?.windowScene?.session else { return }
        UIApplication.shared.requestSceneSessionDestruction(session, options: nil) { error in
            print(error)
        }
    }
}

@objcMembers
class MultitaskRelaunchManager: NSObject {
    private static var pendingKeys: Set<String> = []
    private static let pendingLock = NSLock()
    
    static func scheduleRelaunchIfNeeded(bundleId: String, dataUUID: String, isManualTermination: Bool) {
        let defaults = LCUtils.appGroupUserDefault
        let multitaskMode = MultitaskMode(rawValue: defaults.integer(forKey: "LCMultitaskMode")) ?? .virtualWindow
        guard defaults.bool(forKey: "LCSkipTerminatedScreen"),
              defaults.bool(forKey: "LCRestartTerminatedApp"),
              multitaskMode == .virtualWindow,
              !isManualTermination else { return }
        
        let key = "\(bundleId)#\(dataUUID)"
        guard markPendingIfNeeded(key: key) else { return }
        
        Task {
            defer { clearPending(key: key) }
            try? await Task.sleep(nanoseconds: 500_000_000)
            await relaunchApp(bundleId: bundleId, dataUUID: dataUUID)
        }
    }
    
    private static func markPendingIfNeeded(key: String) -> Bool {
        pendingLock.lock()
        defer { pendingLock.unlock() }
        if pendingKeys.contains(key) {
            return false
        }
        pendingKeys.insert(key)
        return true
    }
    
    private static func clearPending(key: String) {
        pendingLock.lock()
        pendingKeys.remove(key)
        pendingLock.unlock()
    }
    
    private static func relaunchApp(bundleId: String, dataUUID: String) async {
        guard let appModel = await MainActor.run(body: { lookupAppModel(bundleId: bundleId) }),
              appModel.appInfo.lastLaunched.distance(to: .now) > 2
        else {
            return
        }
        
        do {
            try await appModel.runApp(multitask: true, containerFolderName: dataUUID)
        } catch {
            print("Failed to restart \(bundleId): \(error)")
        }
    }
    
    @MainActor private static func lookupAppModel(bundleId: String) -> LCAppModel? {
        let sharedModel = DataManager.shared.model
        if let app = sharedModel.apps.first(where: { $0.appInfo.relativeBundlePath == bundleId }) {
            return app
        }
        return sharedModel.hiddenApps.first(where: { $0.appInfo.relativeBundlePath == bundleId })
    }
}
