//
//  DeactivateAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 3/4/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import SideSign
import CoreData

final class DeactivateAppOperation: BasePipelineOperation<PipelineOperationContext, InstalledApp>, @unchecked Sendable
{
    let app: InstalledApp?
    
    init(app: InstalledApp?, context: PipelineOperationContext) throws {
        self.app = app
        try super.init(context: context)
    }
    
    override func execute(parentProgress: Progress?) async throws -> InstalledApp {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[DeactivateAppOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[DeactivateAppOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)
        
        let backgroundContext = self.context.dbBackgroundContext
        
        guard let app = self.app else {
            throw OperationError.invalidParameters("DeactivateAppOperation: target app is nil")
        }
        
        let appObjectID = app.objectID
        let installedApp = await backgroundContext.perform {
            backgroundContext.object(with: appObjectID) as! InstalledApp
        }

        try await self.performDeactivate(for: installedApp)
        
        let result = await backgroundContext.perform {
            backgroundContext.object(with:appObjectID) as! InstalledApp
        }
        self.setProgress(100)
        return result
    }
    
    @discardableResult
    private func performDeactivate(for installedApp: InstalledApp) async throws -> InstalledApp {
        let appExIdentifiers = installedApp.appExtensions.map { $0.resignedBundleIdentifier }
        let allIdentifiers = [installedApp.resignedBundleIdentifier] + appExIdentifiers

        var removedAny = false
        let count = allIdentifiers.count
        let startProgress = self.progress.completedUnitCount
        let endProgress: Int64 = 90
        let range = endProgress - startProgress
        
        do {
            await CellularRefreshManager.shared.turnOffDataIfNeeded()
            for (index, identifier) in allIdentifiers.enumerated() {
                try await removeProvisioningProfile(identifier)
                if range > 0 {
                    let percent = startProgress + Int64(Double(index + 1) / Double(count) * Double(range))
                    self.setProgress(percent)
                }
                removedAny = true
            }
            await CellularRefreshManager.shared.turnOnDataIfNeeded()
        } catch {
            await CellularRefreshManager.shared.turnOnDataIfNeeded()
            throw error
        }
        guard removedAny else {
            throw OperationError.invalidParameters("DeactivateAppOperation: no profiles found to remove")
        }
        installedApp.isActive = false
        return installedApp
    }
}

