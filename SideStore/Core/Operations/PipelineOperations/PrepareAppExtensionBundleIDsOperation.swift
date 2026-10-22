//
//  PrepareAppExtensionBundleIDsOperation.swift
//  SideStore
//
//  Created by Magesh K on 01/08/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

import Foundation

final class PrepareAppExtensionBundleIDsOperation: BasePipelineOperation<InstallAppOperationContext, Void>, @unchecked Sendable {
    override func execute(parentProgress: Progress?) async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[PrepareAppExtensionBundleIDsOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[PrepareAppExtensionBundleIDsOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        
        if self.context.useMainProfile {
            if let appBundle = self.context.targetAppBundle, let profile = self.context.provisioningProfiles?[self.context.bundleIdentifier] {
                var appexBundleIds: [String: String] = [:]
                for appex in appBundle.appExtensions {
                    appexBundleIds[appex.bundleIdentifier] = appex.bundleIdentifier
                        .replacingOccurrences(of: appBundle.bundleIdentifier, with: profile.bundleIdentifier)
                }
                self.context.appexBundleIds = appexBundleIds
            }
        }
        self.setProgress(100)
    }
}
