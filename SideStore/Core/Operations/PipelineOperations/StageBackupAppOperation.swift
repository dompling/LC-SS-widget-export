//
//  StageBackupAppOperation.swift
//  SideStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

import Foundation
import SideSign

final class StageBackupAppOperation: BasePipelineOperation<InstallAppOperationContext, InstalledApp>, @unchecked Sendable {
    let targetApp: InstalledApp?

    init(app: InstalledApp?, context: InstallAppOperationContext) throws {
        self.targetApp = app
        try super.init(context: context)
    }

    override func execute(parentProgress: Progress?) async throws -> InstalledApp {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[StageBackupAppOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[StageBackupAppOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)
        
        guard let targetApp = self.targetApp else {
            debugLog("[StageBackupAppOperation] Error: target app is nil")
            throw OperationError.invalidParameters("StageBackupAppOperation: target app is nil")
        }
        
        debugLog("[StageBackupAppOperation] Preparing backup app stage for '\(targetApp.name)' (\(targetApp.bundleIdentifier)), target bundleID: '\(context.targetBundleIdentifier)'")
        
        guard ALTApplication(fileURL: targetApp.fileURL) != nil else {
            debugLog("[StageBackupAppOperation] Error: ALTApplication invalid/not found at \(targetApp.fileURL.path)")
            throw OperationError.missingAppBundle(reason: "Could not find application bundle for '\(targetApp.name)' at '\(targetApp.fileURL.lastPathComponent)'")
        }

        self.setProgress(20)
        let temporaryDirectoryURL = context.temporaryDirectory.appendingPathComponent("SideBackup-" + UUID().uuidString)
        debugLog("[StageBackupAppOperation] Creating temp directory at \(temporaryDirectoryURL.path)")
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true, attributes: nil)

        guard let sidebackupFileURL = Bundle.main.url(forResource: "SideBackup", withExtension: "ipa") else {
            debugLog("[StageBackupAppOperation] Error: SideBackup.ipa resource not found in main bundle")
            throw OperationError.invalidParameters("Resource 'SideBackup.ipa' could not be found in the main bundle.")
        }
        debugLog("[StageBackupAppOperation] Found SideBackup.ipa at \(sidebackupFileURL.path)")

        self.setProgress(40)
        debugLog("[StageBackupAppOperation] Unzipping SideBackup.ipa...")
        let unzippedAppBundleURL = try FileManager.default.unzipAppBundle(at: sidebackupFileURL, toDirectory: temporaryDirectoryURL)
        debugLog("[StageBackupAppOperation] Unzipped SideBackup app bundle to \(unzippedAppBundleURL.path)")
        
        guard let sideBackupBundle = ALTApplication(fileURL: unzippedAppBundleURL) else {
            debugLog("[StageBackupAppOperation] Error: Failed to instantiate ALTApplication at \(unzippedAppBundleURL.path)")
            throw OperationError.missingAppBundle(reason: "Unzipped bundle directory could not be located at '\(unzippedAppBundleURL.lastPathComponent)'")
        }

        self.setProgress(70)
        debugLog("[StageBackupAppOperation] Updating Info.plist: CFBundleDisplayName='\(targetApp.name)', CFBundleIdentifier='\(context.targetBundleIdentifier)'")
        var updates: [String: any Sendable] = [
            "CFBundleDisplayName": targetApp.name,
            kCFBundleIdentifierKey as String: context.targetBundleIdentifier
        ]

        let targetAppBundle = ALTApplication(fileURL: targetApp.fileURL)
        var targetAppGroups = (targetAppBundle?.entitlements[.appGroups] as? [String]) ?? []
        if !targetAppGroups.contains(Bundle.baseAltStoreAppGroupID) {
            targetAppGroups.append(Bundle.baseAltStoreAppGroupID)
        }

        // replace sidebackup app's entitlements with target app's entilements (for appgroup!)
        context.additionalEntitlements[.appGroups] = targetAppGroups

        let installedAppUTI: [String: any Sendable] = [
            "UTTypeConformsTo": [],
            "UTTypeDescription": "SideStore Backup App",
            "UTTypeIconFiles": [],
            "UTTypeIdentifier": targetApp.installedBackupAppUTI,
            "UTTypeTagSpecification": [:]
        ]

        var exportedUTIs = sideBackupBundle.infoPlist[Bundle.Info.exportedUTIs] as? [[String: any Sendable]] ?? []
        exportedUTIs.append(installedAppUTI)
        updates[Bundle.Info.exportedUTIs] = exportedUTIs

        if let cachedAppBundle = ALTApplication(fileURL: targetApp.fileURL),
           let icon = cachedAppBundle.icon?.resizing(to: CGSize(width: 180, height: 180)),
           let iconData = icon.pngData() {
            let iconFileURL = unzippedAppBundleURL.appendingPathComponent("AppIcon.png")
            try? iconData.write(to: iconFileURL, options: .atomic)
            updates["CFBundleIcons"] = ["CFBundlePrimaryIcon": ["CFBundleIconFiles": [iconFileURL.lastPathComponent]]]
            debugLog("[StageBackupAppOperation] Saved resized app icon to \(iconFileURL.path)")
        }

        try sideBackupBundle.updateInfoPlist(with: updates)
        debugLog("[StageBackupAppOperation] Updated Info.plist written via sideBackupBundle.updateInfoPlist")

        self.setProgress(90)
        guard let updatedBundle = ALTApplication(fileURL: unzippedAppBundleURL) else {
            debugLog("[StageBackupAppOperation] Error: Failed to reload ALTApplication for staged backup app at \(unzippedAppBundleURL.path)")
            throw OperationError.missingAppBundle(reason: "Failed to reload ALTApplication for staged backup app at '\(unzippedAppBundleURL.lastPathComponent)'")
        }
        context.targetAppBundle = updatedBundle
        debugLog("[StageBackupAppOperation] Successfully set context.appBundle to staged SideBackup app ('\(updatedBundle.bundleIdentifier)')")
        self.setProgress(100)
        return targetApp
    }
}
