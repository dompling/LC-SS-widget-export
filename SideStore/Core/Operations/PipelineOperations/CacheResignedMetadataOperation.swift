//
//  CacheResignedMetadataOperation.swift
//  SideStore
//
//  Created by Magesh K on 13/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SideSign

final class CacheResignedMetadataOperation: BasePipelineOperation<InstallAppOperationContext, Void>, @unchecked Sendable {
    override func execute(parentProgress: Progress?) async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[CacheResignedMetadataOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[CacheResignedMetadataOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        
        guard let targetAppBundle = self.context.resignedAppBundle else {
            debugLog("[CacheResignedMetadataOperation] FAILED: self.context.resignedAppBundle is nil; cannot cache metadata.")
            return
        }
        
        guard let installedApp = self.context.installedApp else {
            debugLog("[CacheResignedMetadataOperation] FAILED: self.context.installedApp is nil; cannot cache metadata.")
            return
        }
        
        let resignedID = installedApp.resignedBundleIdentifier
        if resignedID.isAltStoreAppID {
            debugLog("[CacheResignedMetadataOperation] Skipping caching of resigned metadata for self (\(resignedID)).")
            return
        }
        
        try cacheProvisioningProfiles(for: installedApp)
        try cacheInfoPlist(for: installedApp, targetAppBundle: targetAppBundle)
        try cacheEntitlements(for: installedApp)
        
        self.setProgress(100)
    }
    
    private func cacheProvisioningProfiles(for app: InstalledApp) throws {
        guard let profiles = self.context.provisioningProfiles, !profiles.isEmpty else { return }
        let profilesDirectory = app.directoryURL.appendingPathComponent("ProvisioningProfiles")
        try FileManager.default.createDirectory(at: profilesDirectory, withIntermediateDirectories: true, attributes: nil)
        
        let validProfileIDs = Set(profiles.values.map { $0.bundleIdentifier })
        cleanupStaleFiles(in: profilesDirectory, matchingExtension: "mobileprovision", validIDs: validProfileIDs, description: "profile")
        
        for (_, profile) in profiles {
            let targetID = profile.bundleIdentifier
            let fileURL = profilesDirectory.appendingPathComponent("\(targetID).mobileprovision")
            try profile.data.write(to: fileURL, options: .atomic)
            debugLog("[CacheResignedMetadataOperation] Cached provisioning profile for \(targetID) to \(fileURL.path)")
        }
    }
    
    private func cacheInfoPlist(for app: InstalledApp, targetAppBundle: ALTApplication) throws {
        let infoPlistDirectory = app.directoryURL.appendingPathComponent("Info.plist")
        try FileManager.default.createDirectory(at: infoPlistDirectory, withIntermediateDirectories: true, attributes: nil)
        
        let validBundleIDs = Set(targetAppBundle.allAppBundles.map { $0.bundleIdentifier })
        cleanupStaleFiles(in: infoPlistDirectory, matchingExtension: "plist", validIDs: validBundleIDs, description: "Info.plist")
        
        for bundle in targetAppBundle.allAppBundles {
            let targetID = bundle.bundleIdentifier
            let destURL = infoPlistDirectory.appendingPathComponent("\(targetID).plist")
            do {
                let parser = try InfoPlistParser(bundleURL: bundle.fileURL)
                try parser.write(to: destURL)
                debugLog("[CacheResignedMetadataOperation] Cached resigned Info.plist for \(targetID) to \(destURL.path)")
            } catch {
                debugLog("[CacheResignedMetadataOperation] Failed to cache Info.plist for \(targetID) from \(bundle.fileURL.path): \(error)")
            }
        }
    }
    
    private func cacheEntitlements(for app: InstalledApp) throws {
        guard let profiles = self.context.provisioningProfiles else { return }
        let entitlementsDirectory = app.directoryURL.appendingPathComponent("Entitlements")
        try FileManager.default.createDirectory(at: entitlementsDirectory, withIntermediateDirectories: true, attributes: nil)
        
        let validEntitlementIDs = Set(profiles.values.map { $0.bundleIdentifier })
        cleanupStaleFiles(in: entitlementsDirectory, matchingExtension: "plist", validIDs: validEntitlementIDs, description: "Entitlements")
        
        for (_, profile) in profiles {
            let resignedID = profile.bundleIdentifier
            let fileURL = entitlementsDirectory.appendingPathComponent("\(resignedID).plist")
            let entitlements = self.context.customEntitlementsByBundleID[resignedID] ?? profile.entitlements
            
            if let plistData = try? PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0) {
                try? plistData.write(to: fileURL, options: .atomic)
                debugLog("[CacheResignedMetadataOperation] Cached Entitlements for \(resignedID) to \(fileURL.path)")
            }
        }
    }
    
    private func cleanupStaleFiles(in directory: URL, matchingExtension ext: String, validIDs: Set<String>, description: String) {
        guard let existingFiles = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in existingFiles where file.pathExtension.lowercased() == ext.lowercased() {
            let id = file.deletingPathExtension().lastPathComponent
            if !validIDs.contains(id) {
                try? FileManager.default.removeItem(at: file)
                debugLog("[CacheResignedMetadataOperation] Removed stale \(description): \(file.lastPathComponent)")
            }
        }
    }
    
    static func clearCustomizations(for app: InstalledApp) {
        guard UserDefaults.standard.isClearCustomizationsOnUninstallEnabled else { return }
        
        let bundleID = app.bundleIdentifier
        let resignedBundleID = app.resignedBundleIdentifier
        let appDirectoryURL = app.directoryURL
        
        ProfileManager.shared.setAssignedProfile(nil, for: bundleID)
        if resignedBundleID != bundleID {
            ProfileManager.shared.setAssignedProfile(nil, for: resignedBundleID)
        }
        
        if FileManager.default.fileExists(atPath: appDirectoryURL.path) {
            try? FileManager.default.removeItem(at: appDirectoryURL)
            SideStore.debugLog("[CacheResignedMetadataOperation] Cleared cached app directory: \(appDirectoryURL.path)")
        }
    }
}
