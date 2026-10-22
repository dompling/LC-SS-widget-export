//
//  CleanStagedAppOperation.swift
//  SideStore
//
//  Created by Magesh K on 31/7/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation

final class CleanStagedAppOperation: BasePipelineOperation<InstallAppOperationContext, Void>, @unchecked Sendable {
    
    override func execute(parentProgress: Progress?) async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[CleanStagedAppOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[CleanStagedAppOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)
        
        let tempDir = self.context.temporaryDirectory
        debugLog("[CleanStagedAppOperation] Removing temporary staged app directory: \(tempDir)")
        
        if FileManager.default.fileExists(atPath: tempDir.path) {
            self.setProgress(40)
            do {
                try FileManager.default.removeItem(at: tempDir)
                debugLog("[CleanStagedAppOperation] Successfully removed temporary staged app directory.")
            } catch {
                debugLog("[CleanStagedAppOperation] Failed to remove temporary staged app directory: \(error)")
            }
        }
        self.setProgress(100)
    }
}
