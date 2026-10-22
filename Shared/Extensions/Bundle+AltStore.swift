//
//  Bundle+AltStore.swift
//  AltStore
//
//  Created by Riley Testut on 5/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CodeSignKit

private let appGroupsLock = NSLock()
private nonisolated(unsafe) var appGroupsCache: [URL: (modDate: Date?, groups: [String])] = [:]

// @livecontainer
private extension Bundle {
    @objc dynamic static let activeBundle: Bundle = Bundle.main
    @objc dynamic static let storeAppBundleIdentifier = "com.SideStore.SideStore"
    @objc dynamic static let appbundleIdentifier = "com.SideStore.SideStore"
}

public extension Bundle
{
    struct Info
    {
        public static let activeBundle: Bundle = Bundle.activeBundle
        public static let activeBundleURL: URL = activeBundle.bundleURL
        public static let activeBundleVersion: String = {
            let info = activeBundle.infoDictionary
            let version = (info?["CFBundleShortVersionString"] as? String) ?? "?.?.?"
            let build = (info?["CFBundleVersion"] as? String).map { " (\($0))" } ?? "(????)"
            return NSLocalizedString(String(format: "Version %@%@", version, build), comment: "SideStore Version")
        }()
        public static let activeBundleIdentifier: String = activeBundle.bundleIdentifier!
        public static let storeAppBundleIdentifier = Bundle.storeAppBundleIdentifier
        public static let appbundleIdentifier = Bundle.appbundleIdentifier
 
        public static let certificateID = "ALTCertificateID"
     
        public static let urlTypes = "CFBundleURLTypes"
        public static let exportedUTIs = "UTExportedTypeDeclarations"
        public static let backgroundModes = "UIBackgroundModes"
    }
}

public extension Bundle
{
    var infoPlistURL: URL {
        let infoPlistURL = self.bundleURL.appendingPathComponent("Info.plist")
        return infoPlistURL
    }
    
    var provisioningProfileURL: URL {
        let provisioningProfileURL = self.bundleURL.appendingPathComponent("embedded.mobileprovision")
        return provisioningProfileURL
    }
    
    var certificateURL: URL {
        let certificateURL = self.bundleURL.appendingPathComponent("ALTCertificate.p12")
        return certificateURL
    }
    
    var altstorePlistURL: URL {
        let altstorePlistURL = self.bundleURL.appendingPathComponent("AltStore.plist")
        return altstorePlistURL
    }
}

public extension Bundle
{
    // @livecontainer
    @objc dynamic static let baseAltStoreAppGroupID = "group." + Bundle.Info.appbundleIdentifier

    var appGroups: [String] {
        guard let execURL = self.executableURL else { return [] }

        let modDate = (try? execURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

        return appGroupsLock.withLock {
            if let entry = appGroupsCache[execURL], entry.modDate == modDate {
                return entry.groups
            }

            let groups: [String] = {
                guard let rawEntitlements = try? MachOParser.entitlements(at: execURL),
                      let data = rawEntitlements.data(using: .utf8),
                      let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                      let appGroups = plist["com.apple.security.application-groups"] as? [String] else {
                    return []
                }
                return appGroups
            }()

            appGroupsCache[execURL] = (modDate: modDate, groups: groups)
            return groups
        }
    }
    
    // @livecontainer
    @objc dynamic var altstoreAppGroup: String? {
        let appGroup = self.appGroups.first { $0.contains(Bundle.baseAltStoreAppGroupID) }
        return appGroup
    }
    
}

public extension String {
    var isAltStoreAppID: Bool {
        let activeID   = Bundle.Info.activeBundleIdentifier
        let altstoreID = Bundle.Info.appbundleIdentifier
        
        let matchesActiveBundle   = !activeID.isEmpty && self.contains(activeID)
        let matchesAltStoreBundle = !altstoreID.isEmpty && self.contains(altstoreID)
        
        return matchesActiveBundle || matchesAltStoreBundle
    }
}
