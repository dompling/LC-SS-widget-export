//
//  EmbedSigningCertOperation.swift
//  SideStore
//
//  Created by Magesh K on 8/5/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SideSign

final class EmbedSigningCertOperation: BasePipelineOperation<InstallAppOperationContext, Void>, @unchecked Sendable {
    override func execute(parentProgress: Progress?) async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[EmbedSigningCertOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[EmbedSigningCertOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        
        // 1. Resolve the certificate used for signing this app
        guard let cert = self.context.targetSigningCertificate else
        {
            throw OperationError.invalidParameters("EmbedSigningCertOperation: No signing certificate found in context.")
        }
        
        guard let certData = cert.data else {
            debugLog("[EmbedSigningCertOperation] WARNING: Certificate has no data to embed.")
            return
        }
        
        // 2. Write ALTCertificate.p12 (if p12) or ALTCertificate.der (if der) directly inside the target app bundle
        guard let appBundle = self.context.targetAppBundle else {
            throw OperationError.invalidParameters("EmbedSigningCertOperation: targetAppBundle is missing in context.")
        }
        
        let p12Password = CertificateManager.shared.getPassword(for: cert)
        
        do {
            if let p12Data = try? CertificateManager.convert(cert, password: p12Password) {
                let p12URL = appBundle.fileURL.appendingPathComponent("ALTCertificate.p12")
                try p12Data.write(to: p12URL, options: .atomic)
                debugLog("[EmbedSigningCertOperation] Successfully embedded ALTCertificate.p12 in app bundle: \(p12URL.path)")
            } else {
                let derURL = appBundle.fileURL.appendingPathComponent("ALTCertificate.der")
                try certData.write(to: derURL, options: .atomic)
                debugLog("[EmbedSigningCertOperation] Successfully embedded ALTCertificate.der in app bundle: \(derURL.path)")
            }
        } catch {
            debugLog("[EmbedSigningCertOperation] ERROR: Failed to embed signing certificate into app bundle: \(error)")
            throw error
        }
    }
}
