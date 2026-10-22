//
//  RemoveAppOperation.swift
//  SideStore
//
//  Created by Magesh K on 3/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import CoreData

final class RemoveAppOperation: BasePipelineOperation<InstallAppOperationContext, InstalledApp>, @unchecked Sendable {
    
    override func execute(parentProgress: Progress?) async throws -> InstalledApp {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[RemoveAppOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[RemoveAppOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        guard let installedApp = self.context.installedApp else {
            throw OperationError.invalidParameters("RemoveAppOperation: self.context.installedApp is nil")
        }
        
        let backgroundContext = self.context.dbBackgroundContext
        
        await backgroundContext.perform {
            let installedAppInContext = backgroundContext.object(with: installedApp.objectID) as! InstalledApp
            CacheResignedMetadataOperation.clearCustomizations(for: installedAppInContext)
            backgroundContext.delete(installedAppInContext)
        }
        
        self.setProgress(100)
        return installedApp
    }
}
