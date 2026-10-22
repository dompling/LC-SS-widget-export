//
//  VerifyAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 5/2/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//


import Foundation
import CryptoKit
import SideSign

import RegexBuilder

private extension ALTEntitlement {
    static var ignoredEntitlements: Set<ALTEntitlement> = [
        .applicationIdentifier,
        .teamIdentifier
    ]
}

enum PermissionReviewMode {
    case none
    case all
    case added
}

final class VerifyAppOperation: BasePipelineOperation<InstallAppOperationContext, Bool>, @unchecked Sendable {
    let permissionsMode: PermissionReviewMode
    init(permissionsMode: PermissionReviewMode, context: InstallAppOperationContext) throws {
        self.permissionsMode = permissionsMode
        try super.init(context: context)
    }
    
    override func execute(parentProgress: Progress?) async throws -> Bool {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[VerifyAppOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[VerifyAppOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        guard let appBundle = self.context.targetAppBundle else {
            throw OperationError.invalidParameters("VerifyAppOperation: context.appBundle is nil")
        }
        
        guard !UserDefaults.standard.appVerificationDisabled else {
            debugLog("[VerifyAppOperation] App verification was disabled for \(appBundle.bundleIdentifier), skipping all verification.")
            self.setProgress(100)
            return true
        }
        
        self.setProgress(10)

        // 1. Bundle ID Verification
        if UserDefaults.standard.isBundleIDVerificationEnabled {
            if !["ny.litritt.ignited", "com.litritt.ignited"].contains(where: { $0 == appBundle.bundleIdentifier }) {
                guard appBundle.bundleIdentifier == self.context.bundleIdentifier else {
                    throw VerificationError.mismatchedBundleIdentifiers(sourceBundleID: self.context.bundleIdentifier, appBundle: appBundle)
                }
            }
        } else {
            debugLog("[VerifyAppOperation] Bundle ID verification disabled, skipping check.")
        }
        
        // 2. iOS Version Compatibility Check
        if UserDefaults.standard.isiOSVersionVerificationEnabled {
            guard ProcessInfo.processInfo.isOperatingSystemAtLeast(appBundle.minimumiOSVersion) else {
                throw VerificationError.iOSVersionNotSupported(app: appBundle, requiredOSVersion: appBundle.minimumiOSVersion)
            }
        } else {
            debugLog("[VerifyAppOperation] iOS version verification disabled, skipping check.")
        }
        
        guard let appVersion = context.appVersion else {
            self.setProgress(100)
            return false
        }
        
        guard let ipaURL = context.ipaURL else {
            throw OperationError.invalidParameters("Missing IPA URL for '\(appBundle.name)' in operation context")
        }
        self.setProgress(30)
                            
        // 3. Checksum (SHA-256) Verification
        if UserDefaults.standard.isChecksumVerificationEnabled {
            try await self.verifyHash(of: appBundle, at: ipaURL, matches: appVersion)
        } else {
            debugLog("[VerifyAppOperation] Checksum verification disabled for \(appBundle.bundleIdentifier), skipping hash check.")
        }
        self.setProgress(50)
        
        // 4. File Size Verification
        if UserDefaults.standard.isFileSizeVerificationEnabled {
            try await self.verifyFileSize(of: appBundle, at: ipaURL, matches: appVersion)
        } else {
            debugLog("[VerifyAppOperation] File size verification disabled for \(appBundle.bundleIdentifier), skipping size check.")
        }
        self.setProgress(70)
        
        // 5. Version & Build Version Verification
        if UserDefaults.standard.isAppVersionVerificationEnabled {
            try await self.verifyDownloadedVersion(of: appBundle, matches: appVersion)
        } else {
            debugLog("[VerifyAppOperation] App version verification disabled for \(appBundle.bundleIdentifier), skipping version check.")
        }
        self.setProgress(85)
        
        // 6. Permissions & Entitlements Verification (for V2+ sources)
        if !UserDefaults.standard.permissionCheckingDisabled,
           let source = appVersion.app?.source,
           source.isSourceAtLeastV2
        {
            try await self.verifyPermissions(of: appBundle, match: appVersion)
        }
        self.setProgress(100)
        return true
    }
    
    private func verifyHash(of appBundle: ALTApplication, at ipaURL: URL, @AsyncManaged matches appVersion: AppVersion) async throws {
        // Do nothing if source doesn't provide hash.
        guard let expectedHash = await $appVersion.sha256 else { return }

        let data = try Data(contentsOf: ipaURL, options: .alwaysMapped)
        let sha256Hash = SHA256.hash(data: data)
        let hashString = sha256Hash.compactMap { String(format: "%02x", $0) }.joined()
        
        verboseLog("[VerifyAppOperation] Comparing app hash (\(hashString)) against expected hash (\(expectedHash))...")
        
        guard hashString == expectedHash else { throw VerificationError.mismatchedHash(hashString, expectedHash: expectedHash, app: appBundle) }
    }
    
    private func verifyFileSize(of appBundle: ALTApplication, at ipaURL: URL, @AsyncManaged matches appVersion: AppVersion) async throws {
        let expectedSize = await $appVersion.size
        guard expectedSize > 0 else { return }

        let resourceValues = try ipaURL.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = resourceValues.fileSize else { return }
        
        verboseLog("[VerifyAppOperation] Comparing app file size (\(fileSize) bytes) against expected size (\(expectedSize) bytes)...")
        
        guard Int64(fileSize) == expectedSize else {
            throw VerificationError.mismatchedSize(Int64(fileSize), expectedSize: expectedSize, app: appBundle)
        }
    }
    
    private func verifyDownloadedVersion(of appBundle: ALTApplication, @AsyncManaged matches appVersion: AppVersion) async throws {
        let (version, buildVersion) = await $appVersion.perform {
            ($0.version, $0.buildVersion)
        }
        
        // marketplace buildVersion validation
        if let buildVersion {
            guard buildVersion == appBundle.buildVersion else {
                throw VerificationError.mismatchedBuildVersion(appBundle.buildVersion, expectedVersion: buildVersion, app: appBundle)
            }
        }
        
        if version != appBundle.version {
            throw VerificationError.mismatchedVersion(version: appBundle.version, expectedVersion: version, app: appBundle)
        }
    }
    
    private func verifyPermissions(of appBundle: ALTApplication, @AsyncManaged match appVersion: AppVersion) async throws {
        guard self.permissionsMode != .none else { return }
        guard let storeApp = await $appVersion.app else { throw OperationError.invalidParameters("verifyPermissions requires storeApp to be non-nil") }
        
        // Verify source permissions match first.
        let allPermissions = try await self.verifyPermissions(of: appBundle, match: storeApp)
        
        guard #available(iOS 15, *) else {
            // Only review downloaded app permissions on iOS 15 and above.
            return
        }
        
        let handler = self.context.handler.entitlementsReviewHandler
        switch self.permissionsMode {
        case .none: break
        case .all:
            let allEntitlements = allPermissions.compactMap { $0 as? ALTEntitlement }
            if !allEntitlements.isEmpty {
                try await handler.reviewPermissions(allEntitlements, for: appBundle, mode: .all)
            }
            
        case .added:
            guard let installedApp = self.context.installedApp else {
                throw OperationError.missingAppBundle(reason: "Could not locate installed app for '\(appBundle.name)' to verify added permissions.")
            }
            let installedAppURL = installedApp.fileURL
            guard let previousApp = ALTApplication(fileURL: installedAppURL) else {
                throw OperationError.missingAppBundle(reason: "Could not locate installed bundle for '\(appBundle.name)' at '\(installedAppURL.lastPathComponent)'")
            }
            
            var previousEntitlements = Set(previousApp.entitlements.keys.map { ALTEntitlement(rawValue: $0) })
            for appExtension in previousApp.appExtensions {
                previousEntitlements.formUnion(appExtension.entitlements.keys.map { ALTEntitlement(rawValue: $0) })
            }
            
            // Make sure all entitlements already exist in previousApp.
            let addedEntitlements = Array(allPermissions.lazy.compactMap { $0 as? ALTEntitlement }.filter { !previousEntitlements.contains($0) })
            if !addedEntitlements.isEmpty {
                try await handler.reviewPermissions(addedEntitlements, for: appBundle, mode: .added)
            }
        }
    }
    
    @discardableResult
    private func verifyPermissions(of appBundle: ALTApplication, @AsyncManaged match storeApp: StoreApp) async throws -> [any ALTAppPermission] {
        let entitlements = self.entitlements(for: appBundle)
        let privacyPermissions = self.privacyPermissions(for: appBundle)
        let localPermissions: [any ALTAppPermission] = Array(entitlements) + privacyPermissions
        
        try await self.verifyPermissions(localPermissions: localPermissions, match: storeApp, appBundle: appBundle)
        
        return localPermissions
    }

    private func entitlements(for appBundle: ALTApplication) -> Set<ALTEntitlement> {
        var allEntitlements = Set(appBundle.entitlements.keys.map { ALTEntitlement(rawValue: $0) })
        for appExtension in appBundle.appExtensions {
            allEntitlements.formUnion(appExtension.entitlements.keys.map { ALTEntitlement(rawValue: $0) })
        }
        
        allEntitlements = allEntitlements.filter { !ALTEntitlement.ignoredEntitlements.contains($0) }
        
        if let isDebuggable = appBundle.entitlements[ALTEntitlement.getTaskAllow.rawValue] as? Bool, !isDebuggable {
            allEntitlements.remove(.getTaskAllow)
        }
        
        return allEntitlements
    }

    private func privacyPermissions(for appBundle: ALTApplication) -> [ALTAppPrivacyPermission] {
        return ([appBundle] + appBundle.appExtensions).flatMap { (app) in
            let permissions = app.infoPlist.keys.compactMap { key -> ALTAppPrivacyPermission? in
                if #available(iOS 16, tvOS 16, *) {
                    guard key.wholeMatch(of: Regex.privacyPermission) != nil else { return nil }
                } else {
                    guard key.contains("UsageDescription") else { return nil }
                }
                
                return ALTAppPrivacyPermission(rawValue: key)
            }
            
            return permissions
        }
    }

    private func verifyPermissions(localPermissions: [any ALTAppPermission], @AsyncManaged match storeApp: StoreApp, appBundle: ALTApplication) async throws {
        let sourcePermissions: Set<AnyHashable> = Set(await $storeApp.perform {
            $0.permissions.map { AnyHashable($0.permission) }
        })

        let missingPermissions: [any ALTAppPermission] = localPermissions.filter { permission in
            if sourcePermissions.contains(AnyHashable(permission)) {
                return false
            } else if permission.type == .privacy {
                guard #available(iOS 16, tvOS 16, *) else {
                    return false
                }
                
                if let match = permission.rawValue.firstMatch(of: Regex.privacyPermission),
                   case let legacyPermission = ALTAppPrivacyPermission(rawValue: String(match.1)),
                   sourcePermissions.contains(AnyHashable(legacyPermission)) {
                    return false
                }
            }
            
            return true
        }
        
        do {
            guard missingPermissions.isEmpty else {
                throw VerificationError.undeclaredPermissions(missingPermissions, app: appBundle)
            }
        } catch let error as VerificationError where error.code == .undeclaredPermissions {
            if let recommendedSources = UserDefaults.standard.recommendedSources, let (sourceID, sourceURL) = await $storeApp.perform({
                $0.source.map { ($0.identifier, $0.sourceURL) }
            }) {
                let normalizedSourceURL = try? sourceURL.normalized()
                
                let isRecommended = recommendedSources.contains { $0.identifier == sourceID || (try? $0.sourceURL?.normalized()) == normalizedSourceURL }
                guard !isRecommended else {
                    return
                }
            }
            
            throw error
        }
    }
}
