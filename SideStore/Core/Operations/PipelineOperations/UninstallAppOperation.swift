//
//  UninstallAppOperation.swift
//  SideStore
//
//  Created by Magesh K on 3/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import CoreData

final class UninstallAppOperation: BasePipelineOperation<InstallAppOperationContext, InstalledApp>, @unchecked Sendable {
    
    override func execute(parentProgress: Progress?) async throws -> InstalledApp {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[UninstallAppOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[UninstallAppOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        guard let installedApp = self.context.installedApp else {
            throw OperationError.invalidParameters("UninstallAppOperation.main: self.context.installedApp is nil")
        }
        
        
        let bundleID = await installedApp.managedObjectContext?.perform { installedApp.bundleIdentifier }
        if bundleID?.isAltStoreAppID == true {
            throw OperationError.invalidParameters("SideStore cannot delete itself.")
        }
        
        let resignedBundleIdentifier = await installedApp.managedObjectContext?.perform {
            self.resignedBundleIdentifier(for: installedApp)
        }
        guard let resignedBundleIdentifier else {
            throw OperationError.invalidParameters("UninstallAppOperation: installedApp.managedObjectContext is nil")
        }
        
        // send uninstall payload to device
        do {
            await CellularRefreshManager.shared.turnOffDataIfNeeded()
            try await removeApp(resignedBundleIdentifier)
            await CellularRefreshManager.shared.turnOnDataIfNeeded()
        } catch {
            await CellularRefreshManager.shared.turnOnDataIfNeeded()
            throw error
        }
        
        self.setProgress(100)
        return installedApp
    }
    
    private func resignedBundleIdentifier(for installedApp: InstalledApp) -> String {
        installedApp.resignedBundleIdentifier
    }
}
