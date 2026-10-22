//
//  WidgetDataManager+CoreData.swift
//  AltStore
//
//  Created by Magesh K on 8/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import CoreData
import SideSign

extension WidgetDataManager {
    public static func publishCurrentInstalledAppsIfNeeded(in context: NSManagedObjectContext) async {
        guard !WidgetDataManager.shared.hasWidgetData else { return }
        await publishCurrentInstalledApps(in: context)
    }

    public static func publishCurrentInstalledApps(in context: NSManagedObjectContext) async {
        await context.performAsync {
            let activeFetch = InstalledApp.activeAppsFetchRequest()
            activeFetch.returnsObjectsAsFaults = false
            let activeApps = (try? context.fetch(activeFetch)) ?? []

            let allFetch = InstalledApp.fetchRequest()
            allFetch.returnsObjectsAsFaults = false
            let allApps = (try? context.fetch(allFetch)) ?? []

            let sortedActiveApps = activeApps.sorted { $0.name < $1.name }
            let sortedAllApps = allApps.sorted { $0.name < $1.name }

            var icons: [String: UIImage] = [:]
            for app in sortedAllApps {
                var icon: UIImage? = nil
                if app.bundleIdentifier == StoreApp.altstoreAppID {
                    icon = ALTApplication(fileURL: Bundle.Info.activeBundleURL)?.icon ?? UIImage(named: "SideStore")
                } else if let application = ALTApplication(fileURL: app.fileURL) {
                    icon = application.icon
                }
                if let icon {
                    icons[app.bundleIdentifier] = icon
                }
            }

            let activeItems = sortedActiveApps.map { app in
                WidgetAppItem(
                    name: app.name,
                    bundleIdentifier: app.bundleIdentifier,
                    expirationDate: app.expirationDate,
                    refreshedDate: app.refreshedDate,
                    tintColorHex: app.storeApp?.tintColor?.hexString
                )
            }

            let allItems = sortedAllApps.map { app in
                WidgetAppItem(
                    name: app.name,
                    bundleIdentifier: app.bundleIdentifier,
                    expirationDate: app.expirationDate,
                    refreshedDate: app.refreshedDate,
                    tintColorHex: app.storeApp?.tintColor?.hexString
                )
            }

            WidgetDataManager.shared.publishWidgetData(activeItems: activeItems, allItems: allItems, icons: icons)
        }
    }
}
