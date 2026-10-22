//
//  WidgetModels.swift
//  SideStore
//
//  Created by Magesh K on 8/13/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation

public enum Direction: String, Sendable {
    case up
    case down
}

public struct WidgetAppItem: Codable, Sendable {
    public var name: String
    public var bundleIdentifier: String
    public var expirationDate: Date
    public var refreshedDate: Date
    public var tintColorHex: String?

    public init(name: String, bundleIdentifier: String, expirationDate: Date, refreshedDate: Date, tintColorHex: String?) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.expirationDate = expirationDate
        self.refreshedDate = refreshedDate
        self.tintColorHex = tintColorHex
    }
}

public struct WidgetDataSnapshot: Codable, Sendable {
    public var activeApps: [WidgetAppItem]
    public var allApps: [WidgetAppItem]
    public var lastUpdated: Date

    public init(activeApps: [WidgetAppItem] = [], allApps: [WidgetAppItem] = [], lastUpdated: Date = Date()) {
        self.activeApps = activeApps
        self.allApps = allApps
        self.lastUpdated = lastUpdated
    }
}
