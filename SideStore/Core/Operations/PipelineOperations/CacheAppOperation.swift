//
//  CacheAppOperation.swift
//  SideStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

import Foundation

final class CacheAppOperation: BasePipelineOperation<InstallAppOperationContext, URL?>, @unchecked Sendable {

    override func execute(parentProgress: Progress?) async throws -> URL? {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[CacheAppOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[CacheAppOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)

        guard let appBundle = context.targetAppBundle else {
            debugLog("[CacheAppOperation] context.appBundle is nil")
            self.setProgress(100)
            return nil
        }

        self.setProgress(40)
        let (signature, targetFileURL) = try Self.cachePayload(for: appBundle.fileURL)
        self.context.appBundleFingerprint = signature
        self.setProgress(100)
        return targetFileURL
    }

    @discardableResult
    static func cachePayload(for bundleURL: URL) throws -> (signature: String, targetFileURL: URL) {
        guard let signature = AppBundleFingerprint.compute(for: bundleURL) else {
            throw OperationError.invalidApp(reason: "Failed to compute app bundle fingerprint for '\(bundleURL.lastPathComponent)'")
        }

        let targetFileURL = InstalledApp.payloadURL(forSignature: signature)
        if !FileManager.default.fileExists(atPath: targetFileURL.path) {
            let parentDir = targetFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
            SideStore.debugLog("[CacheAppOperation] Caching app bundle for signature \(signature) to \(targetFileURL.path)")
            try FileManager.default.copyItem(at: bundleURL, to: targetFileURL, shouldReplace: true)
        } else {
            SideStore.debugLog("[CacheAppOperation] Payload already cached for signature \(signature), skipping copy.")
        }

        return (signature, targetFileURL)
    }

    static func pruneUnusedCaches(activeSignatures: Set<String> = [], activeBundleIDs: Set<String>, isActivelyManaging: (String) -> Bool) {
        // 1. Prune unused payloads in Apps/Payloads/
        let payloadsDirectory = InstalledApp.appsDirectoryURL.appendingPathComponent("Payloads")
        if let cachedPayloadDirs = try? FileManager.default.contentsOfDirectory(
            at: payloadsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
        ) {
            for payloadDir in cachedPayloadDirs {
                do {
                    let resourceValues = try payloadDir.resourceValues(forKeys: [.isDirectoryKey, .nameKey])
                    guard let isDirectory = resourceValues.isDirectory, let signature = resourceValues.name else { continue }
                    if isDirectory && !activeSignatures.contains(signature) {
                        SideStore.debugLog("[CacheAppOperation] DELETING UNUSED CACHED PAYLOAD: \(signature)")
                        try FileManager.default.removeItem(at: payloadDir)
                    }
                } catch {
                    SideStore.debugLog("[CacheAppOperation] Failed to remove cached payload directory: \(error)")
                }
            }
        }

        // 2. Prune unused instance directories in Apps/
        do {
            let cachedAppDirectories = try FileManager.default.contentsOfDirectory(
                at: InstalledApp.appsDirectoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
            )
            for appDirectory in cachedAppDirectories {
                do {
                    let resourceValues = try appDirectory.resourceValues(forKeys: [.isDirectoryKey, .nameKey])
                    guard let isDirectory = resourceValues.isDirectory, let bundleID = resourceValues.name else { continue }
                    if bundleID == "Payloads" { continue }
                    
                    if isDirectory && !activeBundleIDs.contains(bundleID) && !isActivelyManaging(bundleID) {
                        SideStore.debugLog("[CacheAppOperation] DELETING CACHED APP: \(bundleID)")
                        try FileManager.default.removeItem(at: appDirectory)
                    }
                } catch {
                    SideStore.debugLog("[CacheAppOperation] Failed to remove cached app directory: \(error)")
                }
            }
        } catch {
            SideStore.debugLog("[CacheAppOperation] Failed to remove cached apps: \(error)")
        }
    }
}
