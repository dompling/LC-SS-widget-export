//
//  UserCustomizationOperation.swift
//  SideStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//


import Foundation
import CoreData
import SideSign

final class UserCustomizationOperation: BasePipelineOperation<InstallAppOperationContext, String?>, @unchecked Sendable {

    override func execute(parentProgress: Progress?) async throws -> String? {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[UserCustomizationOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[UserCustomizationOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)

        if context.isStoreUpdate {
            debugLog("[UserCustomizationOperation] Store app update button clicked; skipping customization modal.")
            self.setProgress(100)
            return nil
        }

        let handler = context.handler.userCustomizationHandler

        guard let targetAppBundle = context.targetAppBundle else {
            throw OperationError.invalidParameters("UserCustomizationOperation: context.targetAppBundle is nil")
        }

        if UserDefaults.standard.customizeInfoPlist {
            let authTeam = try await AuthManager.shared.getAuthenticatedTeam()
            let teamID = authTeam.identifier
            debugLog("[UserCustomizationOperation] targetBundleIdentifier='\(context.targetBundleIdentifier)', authTeamID='\(teamID)', appendTeamID=\(context.appendTeamID)")
            guard !teamID.isEmpty else {
                debugLog("[UserCustomizationOperation] FAILED: authTeamID is empty")
                throw OperationError.invalidParameters("Active developer team identifier is missing.")
            }

            // Fetch installed apps to detect existing installations by authoritative bundle ID
            let installedApps: [InstalledApp] = context.dbBackgroundContext.performAndWait {
                let request = InstalledApp.fetchRequest()
                return (try? context.dbBackgroundContext.fetch(request)) ?? []
            }
            let installedAppIdentities = Dictionary(
                installedApps.compactMap { app -> (String, String)? in
                    (app.bundleIdentifier, app.name)
                },
                uniquingKeysWith: { first, _ in first }
            )

            let initialBundleID: String
            let targets: [InfoPlistTarget]

            if let installedApp = context.installedApp {
                let cachedParser = installedApp.customInfoPlistURL.flatMap { try? InfoPlistParser(plistURL: $0) }
                initialBundleID = cachedParser?.bundleIdentifier ?? installedApp.resignedBundleIdentifier
                let mainPlist = cachedParser?.rawDictionary ?? targetAppBundle.infoPlist

                var list: [InfoPlistTarget] = [
                    InfoPlistTarget(id: initialBundleID, name: targetAppBundle.name, isExtension: false, initialPlist: mainPlist)
                ]

                for ext in targetAppBundle.allAppBundles where ext.isExtension {
                    let matchingExtension = installedApp.appExtensions.first(where: { $0.bundleIdentifier == ext.bundleIdentifier })
                    let extCachedURL = matchingExtension?.customInfoPlistURL
                    let extPlist = extCachedURL.flatMap { try? InfoPlistParser(plistURL: $0).rawDictionary } ?? ext.infoPlist
                    list.append(InfoPlistTarget(id: ext.bundleIdentifier, name: ext.name, isExtension: true, initialPlist: extPlist))
                }
                targets = list
            } else {
                initialBundleID = context.targetBundleIdentifier
                var list: [InfoPlistTarget] = [
                    InfoPlistTarget(id: initialBundleID, name: targetAppBundle.name, isExtension: false, initialPlist: targetAppBundle.infoPlist)
                ]
                for ext in targetAppBundle.allAppBundles where ext.isExtension {
                    list.append(InfoPlistTarget(id: ext.bundleIdentifier, name: ext.name, isExtension: true, initialPlist: ext.infoPlist))
                }
                targets = list
            }

            self.setProgress(40)

            guard let result = try await handler.resolveInfoPlistCustomization(
                targets: targets,
                initialBundleID: initialBundleID,
                appendTeamID: context.appendTeamID,
                installedAppIdentities: installedAppIdentities,
                teamID: teamID
            ) else {
                throw OperationError.cancelled
            }

            context.appendTeamID = result.appendTeamID

            let mainModifiedPlist = result.modifiedPlists[initialBundleID] ?? [:]
            let customID = InfoPlistParser(dictionary: mainModifiedPlist).bundleIdentifier
            if let customID = customID, !customID.isEmpty, customID != context.bundleIdentifier {
                context.customBundleIdentifier = customID
            } else {
                context.customBundleIdentifier = nil
            }

            for (targetID, plist) in result.modifiedPlists {
                let key = (targetID == initialBundleID) ? context.targetBundleIdentifier : targetID
                context.customInfoPlistByBundleID[key] = plist
            }

            // Dynamically link existing installed app if bundle ID matches
            let effectiveCustomID = customID ?? initialBundleID
            let resolvedID = result.appendTeamID && !teamID.isEmpty ? "\(effectiveCustomID).\(teamID)" : effectiveCustomID
            if let matchingApp = installedApps.first(where: { $0.bundleIdentifier == resolvedID }) {
                debugLog("[UserCustomizationOperation] Matched existing installed app: \(matchingApp.name) (\(resolvedID))")
                context.installedApp = matchingApp
            } else {
                debugLog("[UserCustomizationOperation] No matching installed app for \(resolvedID); treating as new install/clone.")
                context.installedApp = nil
            }
        } else if UserDefaults.standard.customizeAppId {
            let initialBundleID = context.targetBundleIdentifier
            self.setProgress(40)
            
            guard let result = try await handler.resolveBundleIDOverride(initialBundleID: initialBundleID) else {
                throw OperationError.cancelled
            }
            
            context.appendTeamID = result.appendTeamID
            if result.customID != context.bundleIdentifier {
                context.customBundleIdentifier = result.customID
            } else {
                context.customBundleIdentifier = nil
            }
        }

        if UserDefaults.standard.customizeEntitlements {
            let authTeam = try await AuthManager.shared.getAuthenticatedTeam()
            let mainTargetID = context.targetBundleIdentifier
            self.setProgress(70)

            let targets: [EntitlementsTarget]
            if let installedApp = context.installedApp {
                let mainEntitlements = installedApp.customEntitlements ?? targetAppBundle.entitlements
                var list: [EntitlementsTarget] = [
                    EntitlementsTarget(
                        id: mainTargetID,
                        name: targetAppBundle.name,
                        isExtension: false,
                        initialEntitlements: mainEntitlements
                    )
                ]

                for ext in targetAppBundle.allAppBundles where ext.isExtension {
                    let matchingExtension = installedApp.appExtensions.first(where: { $0.bundleIdentifier == ext.bundleIdentifier })
                    let extEntitlements = matchingExtension?.customEntitlements ?? ext.entitlements
                    list.append(
                        EntitlementsTarget(
                            id: ext.bundleIdentifier,
                            name: ext.name,
                            isExtension: true,
                            initialEntitlements: extEntitlements
                        )
                    )
                }
                targets = list
            } else {
                var list: [EntitlementsTarget] = [
                    EntitlementsTarget(
                        id: mainTargetID,
                        name: targetAppBundle.name,
                        isExtension: false,
                        initialEntitlements: targetAppBundle.entitlements
                    )
                ]

                for ext in targetAppBundle.allAppBundles where ext.isExtension {
                    list.append(
                        EntitlementsTarget(
                            id: ext.bundleIdentifier,
                            name: ext.name,
                            isExtension: true,
                            initialEntitlements: ext.entitlements
                        )
                    )
                }
                targets = list
            }

            guard let result = try await handler.resolveEntitlementsCustomization(
                targets: targets,
                teamType: authTeam.type
            ) else {
                throw OperationError.cancelled
            }

            for (targetID, targetEntitlements) in result {
                context.customEntitlementsByBundleID[targetID] = targetEntitlements
            }

            if let mainEntitlements = result[mainTargetID] {
                for (key, value) in mainEntitlements {
                    context.additionalEntitlements[ALTEntitlement(key)] = value
                }
            }
        }

        if UserDefaults.standard.customizeAppIcon {
            self.setProgress(85)
            if let iconURL = try await handler.resolveAppIconCustomization(appName: targetAppBundle.name) {
                context.alternateIconMode = .set(iconURL)
            }
        }

        if UserDefaults.standard.customizeProvisioningProfile {
            self.setProgress(95)
            let effectiveBundleID = context.customBundleIdentifier ?? context.targetBundleIdentifier
            let choice = try await handler.resolveProvisioningProfileCustomization(
                appName: targetAppBundle.name,
                bundleID: effectiveBundleID
            )
            switch choice {
            case .profile(let profile):
                context.overrideProvisioningProfile = profile
                ProfileManager.shared.assignProfile(uuid: profile.uuid, for: effectiveBundleID)
            case .defaultProfile, .none:
                break
            }
        }

        self.setProgress(100)
        if UserDefaults.standard.customizeInfoPlist || UserDefaults.standard.customizeAppId || UserDefaults.standard.customizeAppIcon || UserDefaults.standard.customizeProvisioningProfile {
            return context.targetBundleIdentifier
        } else {
            return nil
        }
    }
}
