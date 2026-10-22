//
//  AppsEntry.swift
//  AltWidgetExtension
//
//  Created by Riley Testut on 8/22/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit
import WidgetKit

struct AppSnapshot
{
    var name: String
    var bundleIdentifier: String
    var expirationDate: Date
    var refreshedDate: Date
    
    var tintColor: UIColor?
    var icon: UIImage?
}

extension AppSnapshot
{
    init(item: WidgetAppItem)
    {
        self.name = item.name
        self.bundleIdentifier = item.bundleIdentifier
        self.expirationDate = item.expirationDate
        self.refreshedDate = item.refreshedDate
        
        if let hex = item.tintColorHex {
            self.tintColor = UIColor(hexString: hex)
        } else {
            self.tintColor = nil
        }
        
        self.icon = WidgetDataManager.shared.loadCachedIcon(for: item.bundleIdentifier)
    }
}

extension AppSnapshot
{
    static func makePreviewSnapshots() -> (altstore: AppSnapshot, delta: AppSnapshot, clip: AppSnapshot, longAltStore: AppSnapshot, longDelta: AppSnapshot, longClip: AppSnapshot)
    {
        let shortRefreshedDate = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        let shortExpirationDate = Calendar.current.date(byAdding: .day, value: 7, to: shortRefreshedDate) ?? Date()
        
        let longRefreshedDate = Calendar.current.date(byAdding: .day, value: -100, to: Date()) ?? Date()
        let longExpirationDate = Calendar.current.date(byAdding: .day, value: 365, to: longRefreshedDate) ?? Date()
        
        let altstore = AppSnapshot(name: "AltStore",
                                   bundleIdentifier: "com.rileytestut.AltStore",
                                   expirationDate: shortExpirationDate,
                                   refreshedDate: shortRefreshedDate,
                                   tintColor: .altPrimary,
                                   icon: UIImage(named: "AltStore"))
        
        let delta = AppSnapshot(name: "Delta",
                                bundleIdentifier: "com.rileytestut.Delta",
                                expirationDate: shortExpirationDate,
                                refreshedDate: shortRefreshedDate,
                                tintColor: .deltaPrimary,
                                icon: UIImage(named: "Delta"))
        
        let clip = AppSnapshot(name: "Clip",
                               bundleIdentifier: "com.rileytestut.Clip",
                               expirationDate: shortExpirationDate,
                               refreshedDate: shortRefreshedDate,
                               tintColor: .clipPrimary,
                               icon: UIImage(named: "Clip"))
        
        let longAltStore = altstore.with(refreshedDate: longRefreshedDate, expirationDate: longExpirationDate)
        let longDelta = delta.with(refreshedDate: longRefreshedDate, expirationDate: longExpirationDate)
        let longClip = clip.with(refreshedDate: longRefreshedDate, expirationDate: longExpirationDate)
        
        return (altstore, delta, clip, longAltStore, longDelta, longClip)
    }
    
    private func with(refreshedDate: Date, expirationDate: Date) -> AppSnapshot
    {
        var app = self
        app.refreshedDate = refreshedDate
        app.expirationDate = expirationDate
        
        return app
    }
}
