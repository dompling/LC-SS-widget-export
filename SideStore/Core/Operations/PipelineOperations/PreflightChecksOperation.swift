//
//  PreflightChecksOperation.swift
//  SideStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//


import Foundation
import SideSign

final class PreflightChecksOperation: BasePipelineOperation<StandaloneOperationContext, Bool>, @unchecked Sendable {
    let operations: [AppOperation]
    let handler: PreflightChecksHandler?

    init(operations: [AppOperation], handler: PreflightChecksHandler?, context: StandaloneOperationContext) throws {
        self.operations = operations
        self.handler = handler
        try super.init(context: context)
    }

    override func execute(parentProgress: Progress?) async throws -> Bool {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[PreflightChecksOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[PreflightChecksOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)

        let currentTeam = try await AuthManager.shared.getAuthenticatedTeam()
        let currentTeamID = currentTeam.identifier

        let startProgress = self.progress.completedUnitCount
        let endProgress: Int64 = 90
        let range = endProgress - startProgress
        let count = operations.count
        
        for (index, operation) in operations.enumerated() {
            if range > 0 {
                let percent = startProgress + Int64(Double(index + 1) / Double(count) * Double(range))
                self.setProgress(percent)
            }
            
            let isSideStore = (operation.app as? ALTApplication)?.isAltStoreApp == true ||
                               operation.bundleIdentifier.isAltStoreAppID
            guard isSideStore else { continue }
            guard let installedApp = operation.app as? InstalledApp else { continue }

            let activeResignedID = installedApp.resignedBundleIdentifier
            let activeEffectiveID = installedApp.customBundleIdentifier ?? activeResignedID

            let incomingTargetID: String?
            switch operation {
                case .install(let app, let customBundleIdentifier), .update(let app, let customBundleIdentifier), .reinstall(let app, let customBundleIdentifier):
                    if let customBundleIdentifier = customBundleIdentifier, !customBundleIdentifier.isEmpty {
                        incomingTargetID = customBundleIdentifier
                    } else if !currentTeamID.isEmpty {
                        incomingTargetID = "\(StoreApp.altstoreAppID).\(currentTeamID)"
                    } else if let installedApp = app as? InstalledApp {
                        incomingTargetID = installedApp.customBundleIdentifier ?? installedApp.resignedBundleIdentifier
                    } else {
                        incomingTargetID = nil
                    }
                case .refresh(let installedApp),    .activate(let installedApp),    .deactivate(let installedApp), .deleteApp(let installedApp),
                     .backup(let installedApp),     .restore(let installedApp),     .resign(let installedApp, _),
                     .removeApp(let installedApp),  .removeDeactivatedApp(let installedApp):
                    
                    if !currentTeamID.isEmpty && installedApp.bundleIdentifier == StoreApp.altstoreAppID {
                        incomingTargetID = installedApp.customBundleIdentifier ?? "\(StoreApp.altstoreAppID).\(currentTeamID)"
                    } else {
                        incomingTargetID = installedApp.customBundleIdentifier ?? installedApp.resignedBundleIdentifier
                    }
            }

            guard let targetID = incomingTargetID, targetID != activeEffectiveID && targetID != activeResignedID else { continue }

            debugLog("[PreflightChecksOperation] SideStore bundle ID mismatch detected: target='\(targetID)', active='\(activeEffectiveID)'")

            switch operation {
                case .resign, .install, .reinstall:
                    guard let handler = self.handler else {
                        throw OperationError.cancelled
                    }
                    
                    let shouldContinue = await handler.resolveBundleIDMismatch(
                        targetID: targetID,
                        activeEffectiveID: activeEffectiveID
                    )

                    if !shouldContinue {
                        debugLog("[PreflightChecksOperation] SideStore bundle ID mismatch prompt cancelled by user. Throwing OperationError.cancelled.")
                        throw OperationError.cancelled
                    }

                default: continue
            }
        }
        self.setProgress(100)
        return true
    }
}
