//
//  SideStoreTopShelfProvider.swift
//  SideStore
//
//  Created by Magesh K on 26/08/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

#if os(tvOS)
import Foundation
import UIKit
import TVServices

public final class SideStoreTopShelfProvider: TVTopShelfContentProvider {

    public override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        let snapshot = WidgetDataManager.shared.fetchSnapshot()
        guard !snapshot.activeApps.isEmpty else {
            completionHandler(nil)
            return
        }

        let items: [TVTopShelfSectionedItem] = snapshot.activeApps.map { app in
            let item = TVTopShelfSectionedItem(identifier: app.bundleIdentifier)
            let daysLeft = max(0, Calendar.current.dateComponents([.day], from: Date(), to: app.expirationDate).day ?? 0)
            item.title = "\(app.name) (\(daysLeft)d)"
            item.imageShape = .square

            if let iconDir = FileManager.default.altstoreSharedDirectory?.appendingPathComponent("WidgetIcons", isDirectory: true) {
                let iconURL = iconDir.appendingPathComponent("\(app.bundleIdentifier).png")
                if FileManager.default.fileExists(atPath: iconURL.path) {
                    item.setImageURL(iconURL, for: .screenScale1x)
                    item.setImageURL(iconURL, for: .screenScale2x)
                }
            }

            if let openURL = URL(string: "sidestore://apps/\(app.bundleIdentifier)") {
                item.displayAction = TVTopShelfAction(url: openURL)
            }

            return item
        }

        let section = TVTopShelfItemCollection(items: items)
        section.title = "Installed Apps"

        let content = TVTopShelfSectionedContent(sections: [section])
        completionHandler(content)
    }
}
#endif
