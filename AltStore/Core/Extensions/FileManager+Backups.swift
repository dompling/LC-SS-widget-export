//
//  FileManager+Backups.swift
//  AltStore
//
//  Created by Magesh K on 8/13/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation

public extension FileManager {
    func backupDirectoryURL(for app: InstalledApp) -> URL? {
        return self.backupDirectoryURL(forBundleIdentifier: app.resignedBundleIdentifier)
    }

    func deleteBackup(for app: InstalledApp) throws {
        try self.deleteBackup(forBundleIdentifier: app.resignedBundleIdentifier)
    }
}
