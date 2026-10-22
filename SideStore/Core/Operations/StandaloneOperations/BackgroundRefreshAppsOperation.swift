//
//  BackgroundRefreshAppsOperation.swift
//  AltStore
//
//  Created by Riley Testut on 7/6/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit
import CoreData


private extension CFNotificationName {
    static let requestAppState = CFNotificationName("com.altstore.RequestAppState" as CFString)
    static let appIsRunning = CFNotificationName("com.altstore.AppState.Running" as CFString)
    
    static func requestAppState(for appID: String) -> CFNotificationName {
        let name = String(CFNotificationName.requestAppState.rawValue) + "." + appID
        return CFNotificationName(name as CFString)
    }
    
    static func appIsRunning(for appID: String) -> CFNotificationName {
        let name = String(CFNotificationName.appIsRunning.rawValue) + "." + appID
        return CFNotificationName(name as CFString)
    }
}

private let ReceivedApplicationState: @convention(c) (CFNotificationCenter?, UnsafeMutableRawPointer?, CFNotificationName?, UnsafeRawPointer?, CFDictionary?) -> Void = { (center, observer, name, object, userInfo) in
    guard let name = name, let observer = observer else { return }
    
    let operation = unsafeBitCast(observer, to: BackgroundRefreshAppsOperation.self)
    operation.receivedApplicationState(notification: name)
}

final class BackgroundRefreshAppsOperation: BaseStandaloneOperation<OperationContext, [String: Result<InstalledApp, Error>]>, @unchecked Sendable {
    let installedApps: [InstalledApp]
    
    var presentsFinishedNotification: Bool = true
    var ignoresServerNotFoundError: Bool = true
    
    private let refreshIdentifier: String = UUID().uuidString
    private var runningApplications: Set<String> = []
    
    init(installedApps: [InstalledApp], context: OperationContext) throws {
        self.installedApps = installedApps
        try super.init(context: context)
    }
    
    override func execute(parentProgress: Progress?) async throws -> [String: Result<InstalledApp, Error>] {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[BackgroundRefreshAppsOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[BackgroundRefreshAppsOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)
        
        let dbContext = self.context.dbBackgroundContext
        
        guard !self.installedApps.isEmpty else {
            let error = OperationError.noInstalledApps
            self.scheduleFinishedRefreshingNotification(for: .failure(error), delay: 0)
            throw error
        }

        if UserDefaults.standard.enableEMPforWireguard {
            try await startEMProxy()
        }
        
        defer {
            dbContext.perform {
                self.stopListeningForRunningApps()
            }
        }
        
        do {
            if #available(iOS 17, *) {
                // TODO: iOS 17 and above have a new JIT implementation that is completely broken in SideStore :(
            }

            await dbContext.perform {
                self.startListeningForRunningApps()
            }

            // Wait for 1 second (1 now, 1 later in FindServerOperation) to:
            // a) give us time to discover AltServers
            // b) give other processes a chance to respond to requestAppState notification
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            let filteredApps = await dbContext.perform {
                return self.installedApps.filter { !self.runningApplications.contains($0.bundleIdentifier) }
            }

            if !self.runningApplications.isEmpty {
                self.verboseLog("[BackgroundRefreshAppsOperation] Skipping refreshing running apps: \(self.runningApplications)")
            }

            let results = try await self.refresh(filteredApps)
            self.scheduleFinishedRefreshingNotification(for: .success(results), delay: 0)
            return results
        } catch {
            self.scheduleFinishedRefreshingNotification(for: .failure(error), delay: 0)
            throw error
        }
    }

    private func refresh(_ apps: [InstalledApp]) async throws -> [String: Result<InstalledApp, Error>] {
        return try await withCheckedThrowingContinuation { continuation in
            let group = AppManager.shared.refresh(apps, presentingViewController: nil)
            group.beginInstallationHandler = { [weak self] (installedApp) in
                guard let self = self else { return }
                guard installedApp.bundleIdentifier == StoreApp.altstoreAppID else { return }
                
                if let error = group.context.error {
                    self.scheduleFinishedRefreshingNotification(for: .failure(error))
                } else {
                    var results = group.results
                    results[installedApp.bundleIdentifier] = .success(installedApp)
                    self.scheduleFinishedRefreshingNotification(for: .success(results))
                }
            }
            group.completionHandler = { (results) in
                self.setProgress(100)
                continuation.resume(returning: results)
            }
        }
    }
    
    private func startListeningForRunningApps() {
        let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        
        for installedApp in self.installedApps {
            let appIsRunningNotification = CFNotificationName.appIsRunning(for: installedApp.bundleIdentifier)
            CFNotificationCenterAddObserver(notificationCenter, observer, ReceivedApplicationState, appIsRunningNotification.rawValue, nil, .deliverImmediately)
            
            let requestAppStateNotification = CFNotificationName.requestAppState(for: installedApp.bundleIdentifier)
            CFNotificationCenterPostNotification(notificationCenter, requestAppStateNotification, nil, nil, true)
        }
    }
    
    private func stopListeningForRunningApps() {
        let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        
        for installedApp in self.installedApps {
            let appIsRunningNotification = CFNotificationName.appIsRunning(for: installedApp.bundleIdentifier)
            CFNotificationCenterRemoveObserver(notificationCenter, observer, appIsRunningNotification, nil)
        }
    }
    
    fileprivate func receivedApplicationState(notification: CFNotificationName) {
        let baseName = String(CFNotificationName.appIsRunning.rawValue)
        
        let appID = String(notification.rawValue).replacingOccurrences(of: baseName + ".", with: "")
        self.runningApplications.insert(appID)
    }
    
    private func scheduleFinishedRefreshingNotification(for result: Result<[String: Result<InstalledApp, Error>], Error>, delay: TimeInterval = 5) {
        func scheduleFinishedRefreshingNotification() {
            #if !os(tvOS)
            self.cancelFinishedRefreshingNotification()
            
            let content = UNMutableNotificationContent()
            
            var shouldPresentAlert = true
            
            do {
                let results = try result.get()
                shouldPresentAlert = !results.isEmpty
                
                for (_, result) in results {
                    guard case let .failure(error) = result else { continue }
                    throw error
                }
                
                content.title = NSLocalizedString("Refreshed Apps", comment: "")
                content.body = NSLocalizedString("All apps have been refreshed.", comment: "")
            } catch let opError as OperationError {
                switch opError {
                case .noConnection, .noVPN, .noInstalledApps:
                    shouldPresentAlert = false
                default:
                    self.debugLog("Failed to refresh apps in background: \(opError)")
                    content.title = NSLocalizedString("Failed to Refresh Apps", comment: "")
                    content.body = opError.localizedDescription
                    shouldPresentAlert = true
                }
            } catch {
                self.debugLog("Failed to refresh apps in background: \(error)")
                content.title = NSLocalizedString("Failed to Refresh Apps", comment: "")
                content.body = error.localizedDescription
                shouldPresentAlert = true
            }

            if shouldPresentAlert {
                // Using nil if delay == 0 fixes race condition where multiple notifications can appear (or none).
                let trigger = delay == 0 ? nil : UNTimeIntervalNotificationTrigger(timeInterval: delay + 1, repeats: false)
                
                let request = UNNotificationRequest(identifier: self.refreshIdentifier, content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request)
                
                if delay > 0 {
                    Task {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
                        // If app is still running at this point, we schedule another notification with same identifier.
                        // This prevents the currently scheduled notification from displaying, and starts another countdown timer.
                        // First though, make sure there _is_ still a pending request, otherwise it's been cancelled
                        // and we should stop polling.
                        guard requests.contains(where: { $0.identifier == self.refreshIdentifier }) else { return }
                        
                        scheduleFinishedRefreshingNotification()
                    }
                }
            }
            #else
            NotificationCenter.default.post(name: NSNotification.Name("TVTopShelfItemsDidChangeNotification"), object: nil)
            #endif
        }
        
        if self.presentsFinishedNotification {
            scheduleFinishedRefreshingNotification()
        }        
        
        // Perform synchronously to ensure app doesn't quit before we've finishing saving to disk.
        let dbContext = self.context.dbBackgroundContext
        let childContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        childContext.parent = dbContext
        childContext.performAndWait {
            self.saveRefreshAttempt(result: result, in: childContext)
        }
        dbContext.performAndWait {
            do { try dbContext.save() }
            catch { debugLog("Failed to save parent context for refresh attempt. \(error.localizedDescription)") }
        }
    }
    
    private func saveRefreshAttempt(result: Result<[String: Result<InstalledApp, Error>], Error>, in context: NSManagedObjectContext) {
        _ = RefreshAttempt(identifier: self.refreshIdentifier, result: result, context: context)
        
        do { try context.save() }
        catch { debugLog("Failed to save refresh attempt. \(error.localizedDescription)") }
    }
    
    private func cancelFinishedRefreshingNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [self.refreshIdentifier])
    }
}
