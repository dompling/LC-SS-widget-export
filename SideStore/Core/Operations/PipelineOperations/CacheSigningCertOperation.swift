//
//  CacheSigningCertOperation.swift
//  SideStore
//
//  Created by Magesh K on 8/5/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SideSign

final class CacheSigningCertOperation: BasePipelineOperation<InstallAppOperationContext, Void>, @unchecked Sendable {
    override func execute(parentProgress: Progress?) async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[CacheSigningCertOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[CacheSigningCertOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        
        guard let installedApp = self.context.installedApp else {
            debugLog("[CacheSigningCertOperation] FAILED: self.context.installedApp is nil; cannot cache signing cert.")
            return
        }
        
        let resignedID = installedApp.resignedBundleIdentifier
        if resignedID.isAltStoreAppID {
            debugLog("[CacheSigningCertOperation] Skipping caching of signing cert for self (\(resignedID)) in favor of embedded certificate.")
            return
        }
        
        // 1. Resolve the certificate used for signing this app
        guard let cert = self.context.targetSigningCertificate else
        {
            throw OperationError.invalidParameters("CacheSigningCertOperation: No signing certificate found in context.")
        }
        
        guard let certData = cert.data else {
            debugLog("[CacheSigningCertOperation] WARNING: Certificate has no data to cache.")
            return
        }
        
        // 2. Resolve target App Group directory
        let certURL = installedApp.signingCertificateURL
        let certDirectory = certURL.deletingLastPathComponent()
        
        do {
            try FileManager.default.createDirectory(at: certDirectory, withIntermediateDirectories: true, attributes: nil)
            try certData.write(to: certURL, options: .atomic)
            debugLog("[CacheSigningCertOperation] Successfully cached signing certificate to \(certURL.path)")
        } catch {
            debugLog("[CacheSigningCertOperation] ERROR: Failed to write signing certificate to disk: \(error)")
            throw error
        }
    }
}
