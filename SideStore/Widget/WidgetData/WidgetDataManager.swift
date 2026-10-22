//
//  WidgetDataManager.swift
//  SideStore
//
//  Created by Magesh K on 8/13/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import UIKit
#if !os(tvOS)
import WidgetKit
#else
import TVServices
#endif

public final class WidgetDataManager: @unchecked Sendable {
    public static let shared = WidgetDataManager()

    private let fileName = "widget_data.json"
    private let iconFolderName = "WidgetIcons"
    private let exportFolderName = "LCSS"
    private let exportLock = NSLock()

    private init() {}

    private var containerURL: URL? {
        FileManager.default.altstoreSharedDirectory
    }

    private var jsonFileURL: URL? {
        containerURL?.appendingPathComponent(fileName)
    }

    private var iconDirectoryURL: URL? {
        containerURL?.appendingPathComponent(iconFolderName, isDirectory: true)
    }

    public var hasWidgetData: Bool {
        guard let url = jsonFileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    public func fetchSnapshot() -> WidgetDataSnapshot {
        guard let url = jsonFileURL else {
            print("[WidgetDataManager] fetchSnapshot failed: containerURL or jsonFileURL is nil")
            return WidgetDataSnapshot()
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[WidgetDataManager] fetchSnapshot failed: file does not exist at \(url.path)")
            return WidgetDataSnapshot()
        }
        do {
            let data = try Data(contentsOf: url)
            let snapshot = try JSONDecoder().decode(WidgetDataSnapshot.self, from: data)
            print("[WidgetDataManager] fetchSnapshot success: \(snapshot.activeApps.count) active, \(snapshot.allApps.count) total apps (lastUpdated: \(snapshot.lastUpdated))")
            return snapshot
        } catch {
            print("[WidgetDataManager] fetchSnapshot decode error at \(url.path): \(error)")
            return WidgetDataSnapshot()
        }
    }

    public func loadCachedIcon(for bundleIdentifier: String) -> UIImage? {
        guard let iconDir = iconDirectoryURL else { return nil }
        let fileURL = iconDir.appendingPathComponent("\(bundleIdentifier).png")
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let image = UIImage(contentsOfFile: fileURL.path) else {
            return nil
        }
        return image
    }

    public func publishWidgetData(activeItems: [WidgetAppItem], allItems: [WidgetAppItem], icons: [String: UIImage] = [:]) {
        print("[WidgetDataManager] publishWidgetData: \(activeItems.count) active, \(allItems.count) all items, \(icons.count) icons")
        let snapshot = WidgetDataSnapshot(activeApps: activeItems, allApps: allItems, lastUpdated: Date())
        writeSnapshot(snapshot)
        for (bundleID, iconImage) in icons {
            cacheIcon(iconImage, for: bundleID)
        }
        #if !os(tvOS)
        WidgetCenter.shared.reloadAllTimelines()
        print("[WidgetDataManager] Triggered WidgetCenter.shared.reloadAllTimelines()")
        #else
        NotificationCenter.default.post(name: .TVTopShelfItemsDidChange, object: nil)
        print("[WidgetDataManager] Triggered TVTopShelfItemsDidChange notification")
        #endif
    }

    public func cacheIcon(_ iconImage: UIImage, for bundleIdentifier: String) {
        guard let iconDir = iconDirectoryURL else { return }
        if !FileManager.default.fileExists(atPath: iconDir.path) {
            try? FileManager.default.createDirectory(at: iconDir, withIntermediateDirectories: true)
        }
        let fileURL = iconDir.appendingPathComponent("\(bundleIdentifier).png")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            if let resized = iconImage.resizing(toFill: CGSize(width: 180, height: 180)),
               let pngData = resized.pngData() {
                try? pngData.write(to: fileURL, options: Data.WritingOptions.atomic)
            }
        }
    }

    /// Makes an existing App Group snapshot available in the app's Documents folder
    /// on first launch after upgrading, without requiring an app refresh.
    public func exportExistingSnapshotToDocuments() {
        guard let url = jsonFileURL else { return }
        do {
            let data = try Data(contentsOf: url)
            exportSnapshotToDocuments(data)
        } catch {
            print("[WidgetDataManager] Unable to export existing snapshot: \(error)")
        }
    }

    private func writeSnapshot(_ snapshot: WidgetDataSnapshot) {
        guard let url = jsonFileURL else {
            print("[WidgetDataManager] writeSnapshot failed: jsonFileURL is nil")
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: Data.WritingOptions.atomic)
            print("[WidgetDataManager] Successfully wrote snapshot JSON to \(url.path) (\(data.count) bytes)")
            exportSnapshotToDocuments(data)
        } catch {
            print("[WidgetDataManager] Failed to write snapshot JSON: \(error)")
        }
    }

    /// Best-effort local export for Files / Shortcuts. Never fails app refresh.
    /// Keep the latest snapshot when startup and background refresh overlap.
    private func exportSnapshotToDocuments(_ data: Data) {
        exportLock.lock()
        defer { exportLock.unlock() }

        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("[WidgetDataManager] Export skipped: Documents unavailable")
            return
        }

        let directoryURL = documentsURL.appendingPathComponent(exportFolderName, isDirectory: true)
        let exportURL = directoryURL.appendingPathComponent(fileName)
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            if let existing = try? Data(contentsOf: exportURL) {
                if existing == data { return }
                let decoder = JSONDecoder()
                if let old = try? decoder.decode(WidgetDataSnapshot.self, from: existing),
                   let incoming = try? decoder.decode(WidgetDataSnapshot.self, from: data),
                   old.lastUpdated > incoming.lastUpdated {
                    print("[WidgetDataManager] Export skipped: existing snapshot is newer")
                    return
                }
            }

            try data.write(to: exportURL, options: .atomic)
            print("[WidgetDataManager] Exported snapshot to \(exportURL.path) (\(data.count) bytes)")
        } catch {
            print("[WidgetDataManager] Export failed: \(error)")
        }
    }
}

public extension WidgetDataManager {
    static let sharedDefaults: UserDefaults? = {
        guard let appGroup = Bundle.main.altstoreAppGroup else { return nil }
        return UserDefaults(suiteName: appGroup)
    }()

    private static let isVerboseLoggingKey = "isAltWidgetVerboseLoggingEnabled"

    var isVerboseLoggingEnabled: Bool {
        get {
            guard let defaults = Self.sharedDefaults else { return true }
            if defaults.object(forKey: Self.isVerboseLoggingKey) == nil {
                return true
            }
            return defaults.bool(forKey: Self.isVerboseLoggingKey)
        }
        set {
            Self.sharedDefaults?.set(newValue, forKey: Self.isVerboseLoggingKey)
        }
    }
}

