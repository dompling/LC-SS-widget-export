//
//  RemoveBackupDataOperation.swift
//  AltStore
//
//  Created by Riley Testut on 5/13/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

final class RemoveBackupDataOperation: BasePipelineOperation<InstallAppOperationContext, Bool>, @unchecked Sendable
{
    private let coordinator = NSFileCoordinator()
    private let coordinatorQueue = OperationQueue()
    
    override func execute(parentProgress: Progress?) async throws -> Bool {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[RemoveBackupDataOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[RemoveBackupDataOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)
        
        guard let installedApp = self.context.installedApp else {
            throw OperationError.invalidParameters("RemoveBackupDataOperation.main: self.context.installedApp is nil")
        }
        
        self.setProgress(30)
        let backupDirectoryURL: URL? = await installedApp.managedObjectContext?.perform {
            self.backupDirectoryURL(for: installedApp)
        }
        guard let backupDirectoryURL else {
            throw OperationError.missingAppGroup(name: installedApp.bundleIdentifier)
        }
        
        guard FileManager.default.fileExists(atPath: backupDirectoryURL.path) else {
            debugLog("[RemoveBackupDataOperation] Backup directory does not exist, nothing to remove: \(backupDirectoryURL.path)")
            self.setProgress(100)
            return true
        }
        
        self.setProgress(60)
        let intent = NSFileAccessIntent.writingIntent(with: backupDirectoryURL, options: [.forDeleting])
        try await self.coordinator.coordinate(with: [intent], queue: self.coordinatorQueue)
        
        self.setProgress(80)
        try self.removeBackupItem(at: intent.url, backupDirectoryURL: backupDirectoryURL, coordinatorError: nil)
        
        self.setProgress(100)
        return true
    }
    
    private func backupDirectoryURL(for installedApp: InstalledApp) -> URL? {
        FileManager.default.backupDirectoryURL(for: installedApp)
    }
    
    private func removeBackupItem(at url: URL, backupDirectoryURL: URL, coordinatorError: Error?) throws {
        if let coordinatorError { throw coordinatorError }
        guard FileManager.default.fileExists(atPath: url.path) else {
            debugLog("[RemoveBackupDataOperation] Backup directory does not exist at coordinated URL: \(url.path)")
            return
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            debugLog("[RemoveBackupDataOperation] Backup directory already absent: \(url.path)")
        } catch {
            debugLog("[RemoveBackupDataOperation] Failed to remove app backup directory \(backupDirectoryURL.lastPathComponent). \(error.localizedDescription)")
            throw error
        }
    }
}
