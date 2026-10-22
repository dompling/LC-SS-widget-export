//
//  InjectBatchProfilesOperation.swift
//  SideStore
//
//  Created by Magesh K on 14/09/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import CoreData
import SideSign

final class InjectBatchProfilesOperation: BaseStandaloneOperation<StandaloneOperationContext, Void>, @unchecked Sendable {
    let batches: [PendingProfileBatch]
    var onAppCompleted: (@Sendable (String) -> Void)?

    init(
        batches: [PendingProfileBatch],
        context: StandaloneOperationContext,
        onAppCompleted: (@Sendable (String) -> Void)? = nil
    ) throws {
        self.batches = batches
        self.onAppCompleted = onAppCompleted
        try super.init(context: context)
    }

    override func execute(parentProgress: Progress?) async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[InjectBatchProfilesOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[InjectBatchProfilesOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)

        guard !self.batches.isEmpty else {
            debugLog("[InjectBatchProfilesOperation] No pending profiles collected across batch, skipping")
            return
        }

        debugLog("[InjectBatchProfilesOperation] Running batch injection for \(self.batches.count) app(s)")

        await CellularRefreshManager.shared.turnOffDataIfNeeded()
        for batch in self.batches {
            debugLog("[InjectBatchProfilesOperation] Installing \(batch.profiles.count) profile(s) for \(batch.bundleID)...")
            for profileData in batch.profiles {
                try await installProvisioningProfiles(profileData)
            }

            if let installedApp = batch.app, let dbContext = installedApp.managedObjectContext {
                debugLog("[InjectBatchProfilesOperation] Updating database record for \(batch.bundleID)...")
                try await dbContext.perform {
                    if let certStatus = batch.certStatus {
                        installedApp.certificateStatus = certStatus
                    }
                    if dbContext.hasChanges {
                        try dbContext.save()
                    }
                }
            }

            self.onAppCompleted?(batch.bundleID)
            debugLog("[InjectBatchProfilesOperation] Successfully processed \(batch.bundleID)")
        }
        await CellularRefreshManager.shared.turnOnDataIfNeeded()
        debugLog("[InjectBatchProfilesOperation] Batch profile injection completed for all \(self.batches.count) app(s)")
        self.setProgress(100)
    }
}
