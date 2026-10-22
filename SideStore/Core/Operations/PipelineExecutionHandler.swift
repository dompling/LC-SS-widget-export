//
//  PipelineExecutionHandler.swift
//  SideStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SideSign

protocol PipelineExecutionHandler: AnyObject, Sendable {
    var preflightChecksHandler: PreflightChecksHandler { get }
    var entitlementsReviewHandler: EntitlementsReviewHandler { get }
    var extensionRemovalHandler: ExtensionRemovalHandler { get }
    var unsupportedVersionHandler: UnsupportedVersionHandler { get }
    var installAppHandler: InstallAppHandler { get }
    var userCustomizationHandler: UserCustomizationHandler { get }
}



protocol PreflightChecksHandler: AnyObject, Sendable {
    func resolveBundleIDMismatch(targetID: String, activeEffectiveID: String) async -> Bool
    var isResignActive: Bool { get }
}

protocol EntitlementsReviewHandler: AnyObject, Sendable {
    func reviewPermissions(_ permissions: [ALTEntitlement], for app: AppProtocol, mode: PermissionReviewMode) async throws
}

enum ExtensionRemovalDecision: Sendable {
    case cancel
    case keepAll(useMainProfile: Bool)
    case removeAll
    case removeSelected(Set<ALTApplication>)
}

protocol ExtensionRemovalHandler: AnyObject, Sendable {
    func selectAppExtensionsToRemove(
        appBundle: ALTApplication,
        localAppExtensions: [ALTApplication],
        excessExtensions: Set<ALTApplication>
    ) async throws -> ExtensionRemovalDecision
}

protocol UnsupportedVersionHandler: AnyObject, Sendable {
    func resolveUnsupportediOSVersion(errorDescription: String, appName: String, compatibleVersion: String) async throws -> Bool
}

protocol InstallAppHandler: AnyObject, Sendable {
    func requestBackgroundSuspension() async
    func suspendToHomeScreen() async
    func isAppInForeground() async -> Bool
}

enum AppGroupResolution: Sendable {
    case correctAndProceed(String)
    case keepOriginal(String)
}

enum ProfileCustomizationChoice: Sendable {
    case defaultProfile
    case profile(ALTProvisioningProfile)
}

protocol UserCustomizationHandler: AnyObject, Sendable {
    func resolveBundleIDOverride(initialBundleID: String) async throws -> (customID: String, appendTeamID: Bool)?
    func resolveInfoPlistCustomization(
        targets: [InfoPlistTarget],
        initialBundleID: String,
        appendTeamID: Bool,
        installedAppIdentities: [String: String],
        teamID: String
    ) async throws -> (modifiedPlists: [String: [String: any Sendable]], appendTeamID: Bool)?
    func resolveInfoPlistCustomization(
        initialPlist: [String: any Sendable],
        initialBundleID: String,
        appendTeamID: Bool,
        installedAppIdentities: [String: String],
        teamID: String
    ) async throws -> (modifiedPlist: [String: any Sendable], appendTeamID: Bool)?
    func resolveEntitlementsCustomization(
        targets: [EntitlementsTarget],
        teamType: ALTTeamType
    ) async throws -> [String: [String: any Sendable]]?
    func resolveEntitlementsCustomization(
        initialEntitlements: [String: any Sendable],
        bundleID: String,
        teamType: ALTTeamType
    ) async throws -> [String: any Sendable]?
    func resolveAppGroupMismatch(originalGroup: String, correctedGroup: String) async throws -> AppGroupResolution
    func resolveAppIconCustomization(appName: String) async throws -> URL?
    func resolveProvisioningProfileCustomization(appName: String, bundleID: String) async throws -> ProfileCustomizationChoice?
}

