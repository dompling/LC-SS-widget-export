//
//  BackupEngine.swift
//  SideBackup
//
//  Created by Magesh K on 2/7/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation

extension ErrorUserInfoKey {
    static let sourceFile: String = "alt_sourceFile"
    static let sourceFileLine: String = "alt_sourceFileLine"
}

extension Error {
    var sourceDescription: String? {
        guard let sourceFile = (self as NSError).userInfo[ErrorUserInfoKey.sourceFile] as? String,
              let sourceFileLine = (self as NSError).userInfo[ErrorUserInfoKey.sourceFileLine] else {
            return nil
        }
        return "(\((sourceFile as NSString).lastPathComponent), Line \(sourceFileLine))"
    }
}

struct BackupErrorLocalizer {
    static func description(for context: BackupError.Context) -> String {
        switch context {
        case .createBackup:
            return NSLocalizedString("Unable to create backup directory.", comment: "")
        case .createGroupBackup:
            return NSLocalizedString("Unable to create app group backup directory.", comment: "")
        case .accessBackup:
            return NSLocalizedString("Unable to access backup.", comment: "")
        case .readGroupBackup:
            return NSLocalizedString("Unable to read app group backup.", comment: "")
        }
    }
    
    static func failureReason(for code: BackupError.Code) -> String {
        switch code {
        case .invalidBundleID:
            return NSLocalizedString("The bundle identifier is invalid.", comment: "")
        case .appGroupNotFound(let appGroup):
            if let appGroup = appGroup {
                return String(format: NSLocalizedString("The app group “%@” could not be found.", comment: ""), appGroup)
            } else {
                return NSLocalizedString("The AltStore app group could not be found.", comment: "")
            }
        case .randomError:
            return NSLocalizedString("A random error occurred.", comment: "")
        }
    }
}

struct BackupError: ALTLocalizedError {
    enum Code: ALTErrorEnum, RawRepresentable {
        case invalidBundleID
        case appGroupNotFound(String?)
        case randomError // Used for debugging.
        
        var errorFailureReason: String {
            return BackupErrorLocalizer.failureReason(for: self)
        }
        
        static let errorDomain: String = "com.sidestore.BackupError"
        
        var rawValue: Int {
            switch self {
            case .invalidBundleID: return 0
            case .appGroupNotFound: return 1
            case .randomError: return 2
            }
        }
        
        init?(rawValue: Int) {
            switch rawValue {
            case 0: self = .invalidBundleID
            case 1: self = .appGroupNotFound(nil)
            case 2: self = .randomError
            default: return nil
            }
        }
    }
    
    enum Context {
        case createBackup
        case createGroupBackup
        case accessBackup
        case readGroupBackup
    }
    
    let code: Code
    let sourceFile: String
    let sourceFileLine: Int
    var failure: String?

    var errorTitle: String?
    var errorFailure: String?

    var failureReason: String? {
        return BackupErrorLocalizer.failureReason(for: self.code)
    }
    
    var errorUserInfo: [String : Any] {
        let userInfo: [String: Any?] = [
            NSLocalizedDescriptionKey: self.errorDescription,
            NSLocalizedFailureReasonErrorKey: self.failureReason,
            NSLocalizedFailureErrorKey: self.failure,
            ErrorUserInfoKey.sourceFile: self.sourceFile,
            ErrorUserInfoKey.sourceFileLine: self.sourceFileLine
        ]
        return userInfo.compactMapValues { $0 }
    }
    
    var description: String {
        return "\(errorTitle ?? "Unknown Error"): \(failureReason ?? "No reason available")"
    }

    init(_ code: Code, context: Context, file: String = #file, line: Int = #line) {
        self.code = code
        self.failure = BackupErrorLocalizer.description(for: context)
        self.sourceFile = file
        self.sourceFileLine = line
        self.errorTitle = NSLocalizedString("Backup Error", comment: "")
        self.errorFailure = self.failure
    }
}

final class CopyProgressTracker: @unchecked Sendable {
    var copiedBytes: Int64 = 0
    let totalBytes: Int64
    let progressHandler: (@Sendable (Int64, Int64) -> Void)?

    init(totalBytes: Int64, progressHandler: (@Sendable (Int64, Int64) -> Void)?) {
        self.totalBytes = totalBytes
        self.progressHandler = progressHandler
        self.progressHandler?(0, totalBytes)
    }

    func add(bytes: Int64) {
        self.copiedBytes += bytes
        self.progressHandler?(self.copiedBytes, self.totalBytes)
    }
    
    func complete() {
        self.progressHandler?(self.totalBytes, self.totalBytes)
    }
}

final class BackupEngine: NSObject, Sendable {
    static let shared = BackupEngine()
    private let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "SideBackup-BackupQueue"
        return queue
    }()
    
    private override init() {
        super.init()
    }
    
    func performBackup(skipNonCopyable: Bool = false, progressHandler: (@Sendable (_ copiedBytes: Int64, _ totalBytes: Int64) -> Void)? = nil) async throws {
        let logger = try ConsoleLog.getConsoleLog()
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            throw BackupError(.invalidBundleID, context: .createBackup)
        }
        
        guard
            let altstoreAppGroup = Bundle.main.altstoreAppGroup,
            let sharedDirectoryURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: altstoreAppGroup)
        else {
            throw BackupError(.appGroupNotFound(nil), context: .createBackup)
        }
        
        let backupsDirectory = sharedDirectoryURL.appendingPathComponent("Backups")
        
        // Use temporary directory to prevent messing up successful backup with incomplete one.
        let temporaryAppBackupDirectory = backupsDirectory.appendingPathComponent("Temp", isDirectory: true)
                                                          .appendingPathComponent(UUID().uuidString)
        let appBackupDirectory = backupsDirectory.appendingPathComponent(bundleIdentifier)
        
        let writingIntent = NSFileAccessIntent.writingIntent(with: temporaryAppBackupDirectory, options: [])
        let replacementIntent = NSFileAccessIntent.writingIntent(with: appBackupDirectory, options: [.forReplacing])
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let fileCoordinator = NSFileCoordinator(filePresenter: nil)
            fileCoordinator.coordinate(with: [writingIntent, replacementIntent], queue: self.operationQueue) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                do {
                    try self.performBackupCoordinated(temporaryAppBackupDirectory: temporaryAppBackupDirectory, appBackupDirectory: appBackupDirectory, altstoreAppGroup: altstoreAppGroup, skipNonCopyable: skipNonCopyable, progressHandler: progressHandler, logger: logger)
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func restoreBackup(skipNonCopyable: Bool = false, progressHandler: (@Sendable (_ copiedBytes: Int64, _ totalBytes: Int64) -> Void)? = nil) async throws {
        let logger = try ConsoleLog.getConsoleLog()
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            throw BackupError(.invalidBundleID, context: .accessBackup)
        }
        
        guard
            let altstoreAppGroup = Bundle.main.altstoreAppGroup,
            let sharedDirectoryURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: altstoreAppGroup)
        else {
            throw BackupError(.appGroupNotFound(nil), context: .accessBackup)
        }
        
        let backupsDirectory = sharedDirectoryURL.appendingPathComponent("Backups")
        let appBackupDirectory = backupsDirectory.appendingPathComponent(bundleIdentifier)
        
        let readingIntent = NSFileAccessIntent.readingIntent(with: appBackupDirectory, options: [])
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let fileCoordinator = NSFileCoordinator(filePresenter: nil)
            fileCoordinator.coordinate(with: [readingIntent], queue: self.operationQueue) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                do {
                    try self.restoreBackupCoordinated(appBackupDirectory: appBackupDirectory, altstoreAppGroup: altstoreAppGroup, skipNonCopyable: skipNonCopyable, progressHandler: progressHandler, logger: logger)
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func performBackupCoordinated(temporaryAppBackupDirectory: URL, appBackupDirectory: URL, altstoreAppGroup: String, skipNonCopyable: Bool, progressHandler: (@Sendable (Int64, Int64) -> Void)?, logger: ConsoleLog) throws {
        do {
            let mainGroupBackupDirectory = temporaryAppBackupDirectory.appendingPathComponent("App")
            try FileManager.default.createDirectory(at: mainGroupBackupDirectory, withIntermediateDirectories: true, attributes: nil)
            
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let libraryDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            
            var totalBytes: Int64 = FileManager.default.directorySize(at: documentsDirectory) + FileManager.default.directorySize(at: libraryDirectory)
            for appGroup in Bundle.main.appGroups where appGroup != altstoreAppGroup {
                if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
                    totalBytes += FileManager.default.directorySize(at: appGroupURL)
                }
            }
            
            let tracker = CopyProgressTracker(totalBytes: totalBytes, progressHandler: progressHandler)
            
            let backupDocumentsDirectory = mainGroupBackupDirectory.appendingPathComponent(documentsDirectory.lastPathComponent)
            if FileManager.default.fileExists(atPath: backupDocumentsDirectory.path) {
                try FileManager.default.removeItem(at: backupDocumentsDirectory)
            }
            if FileManager.default.fileExists(atPath: documentsDirectory.path) {
                try FileManager.default.copyDirectoryContents(at: documentsDirectory, to: backupDocumentsDirectory, options: [.skipsHiddenFiles], skipNonCopyable: skipNonCopyable, tracker: tracker, logger: logger)
            }
            debugLog(logger, "[SideBackup] Copied Documents directory from \(documentsDirectory) to \(backupDocumentsDirectory)")
            
            let backupLibraryDirectory = mainGroupBackupDirectory.appendingPathComponent(libraryDirectory.lastPathComponent)
            if FileManager.default.fileExists(atPath: backupLibraryDirectory.path) {
                try FileManager.default.removeItem(at: backupLibraryDirectory)
            }
            if FileManager.default.fileExists(atPath: libraryDirectory.path) {
                try FileManager.default.copyDirectoryContents(at: libraryDirectory, to: backupLibraryDirectory, options: [.skipsHiddenFiles], skipNonCopyable: skipNonCopyable, tracker: tracker, logger: logger)
            }
            debugLog(logger, "[SideBackup] Copied Library directory from \(libraryDirectory) to \(backupLibraryDirectory)")
            
            for appGroup in Bundle.main.appGroups where appGroup != altstoreAppGroup {
                guard let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
                    throw BackupError(.appGroupNotFound(appGroup), context: .createGroupBackup)
                }
                
                let backupAppGroupURL = temporaryAppBackupDirectory.appendingPathComponent(appGroup)
                try FileManager.default.copyDirectoryContents(at: appGroupURL, to: backupAppGroupURL, options: [.skipsHiddenFiles], skipNonCopyable: skipNonCopyable, tracker: tracker, logger: logger)
            }
            
            // Replace previous backup with new backup.
            _ = try FileManager.default.replaceItemAt(appBackupDirectory, withItemAt: temporaryAppBackupDirectory)
            tracker.complete()
            
            debugLog(logger, "[SideBackup] Replaced previous backup with new backup: \(temporaryAppBackupDirectory)")
        } catch {
            do {
                try FileManager.default.removeItem(at: temporaryAppBackupDirectory)
            } catch {
                debugLog(logger, "[SideBackup] Failed to remove temporary directory. \(error)")
            }
            throw error
        }
    }
    
    private func restoreBackupCoordinated(appBackupDirectory: URL, altstoreAppGroup: String, skipNonCopyable: Bool, progressHandler: (@Sendable (Int64, Int64) -> Void)?, logger: ConsoleLog) throws {
        let mainGroupBackupDirectory = appBackupDirectory.appendingPathComponent("App")
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let backupDocumentsDirectory = mainGroupBackupDirectory.appendingPathComponent(documentsDirectory.lastPathComponent)
        
        let libraryDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let backupLibraryDirectory = mainGroupBackupDirectory.appendingPathComponent(libraryDirectory.lastPathComponent)
        
        var totalBytes: Int64 = FileManager.default.directorySize(at: backupDocumentsDirectory) + FileManager.default.directorySize(at: backupLibraryDirectory)
        for appGroup in Bundle.main.appGroups where appGroup != altstoreAppGroup {
            let backupAppGroupURL = appBackupDirectory.appendingPathComponent(appGroup)
            totalBytes += FileManager.default.directorySize(at: backupAppGroupURL)
        }
        
        let tracker = CopyProgressTracker(totalBytes: totalBytes, progressHandler: progressHandler)
        
        try FileManager.default.copyDirectoryContents(at: backupDocumentsDirectory, to: documentsDirectory, options: [], skipNonCopyable: skipNonCopyable, tracker: tracker, logger: logger)
        try FileManager.default.copyDirectoryContents(at: backupLibraryDirectory, to: libraryDirectory, options: [], skipNonCopyable: skipNonCopyable, tracker: tracker, logger: logger)
        
        for appGroup in Bundle.main.appGroups where appGroup != altstoreAppGroup {
            guard let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
                throw BackupError(.appGroupNotFound(appGroup), context: .readGroupBackup)
            }
            
            let backupAppGroupURL = appBackupDirectory.appendingPathComponent(appGroup)
            try FileManager.default.copyDirectoryContents(at: backupAppGroupURL, to: appGroupURL, options: [], skipNonCopyable: skipNonCopyable, tracker: tracker, logger: logger)
        }
        tracker.complete()
    }
}

private extension FileManager {
    func directorySize(at url: URL) -> Int64 {
        guard self.fileExists(atPath: url.path) else { return 0 }
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = self.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                  values.isRegularFile ?? false,
                  let size = values.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }

    func copyDirectoryContents(
        at sourceDirectoryURL: URL,
        to destinationDirectoryURL: URL,
        options: FileManager.DirectoryEnumerationOptions = [],
        skipNonCopyable: Bool = false,
        tracker: CopyProgressTracker?,
        logger: ConsoleLog
    ) throws {
        guard self.fileExists(atPath: sourceDirectoryURL.path) else { return }
        
        if !self.fileExists(atPath: destinationDirectoryURL.path) {
            try self.createDirectory(at: destinationDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        let contents = try self.contentsOfDirectory(at: sourceDirectoryURL, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: options)
        var successCount = 0
        var failureCount = 0
        
        for fileURL in contents {
            let resValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDirectory = resValues?.isDirectory ?? false
            let fileSize = Int64(resValues?.fileSize ?? 0)
            let lastComponent = fileURL.lastPathComponent
            let destinationURL = destinationDirectoryURL.appendingPathComponent(lastComponent)
            
            if self.fileExists(atPath: destinationURL.path) {
                do {
                    let merged = try removeItemRetrying(at: destinationURL, isDirectory: isDirectory, fallbackMerge: {
                        try self.copyDirectoryContents(at: fileURL, to: destinationURL, options: options, skipNonCopyable: skipNonCopyable, tracker: tracker, logger: logger)
                    }, logger: logger)
                    if merged {
                        successCount += 1
                        continue
                    }
                } catch let removeError where isLockingError(removeError) {
                    // Destination item exists and is locked (e.g. a Snapshot dir held open by a live app).
                    // The existing copy is already in place — warn and skip rather than abort the whole backup.
                    failureCount += 1
                    debugLog(logger, "[SideBackup] Backup: Skipping '\(lastComponent)' — destination is locked and cannot be cleared: \(removeError.localizedDescription)")
                    continue
                } catch let removeError where isFileExistsError(removeError) {
                    // NSFileWriteFileExistsError — item already exists and we couldn't remove it; skip safely.
                    failureCount += 1
                    debugLog(logger, "[SideBackup] Backup: Skipping '\(lastComponent)' — destination already exists and remove failed (516): \(removeError.localizedDescription)")
                    continue
                }
            }
            
            do {
                if isDirectory {
                    try self.copyDirectoryContents(at: fileURL, to: destinationURL, options: options, skipNonCopyable: skipNonCopyable, tracker: tracker, logger: logger)
                } else {
                    try copyItemRetrying(from: fileURL, to: destinationURL, skipNonCopyable: skipNonCopyable, logger: logger)
                    tracker?.add(bytes: fileSize)
                }
                successCount += 1
            } catch let copyError where isLockingError(copyError) {
                // Destination got re-created between our remove and copy (race with a live app).
                // Warn and skip — the existing item remains in the destination.
                failureCount += 1
                debugLog(logger, "[SideBackup] Backup: Skipping '\(lastComponent)' — copy failed due to locking: \(copyError.localizedDescription)")
                continue
            } catch let copyError where isFileExistsError(copyError) {
                // Item re-appeared at destination — skip it, existing copy is fine.
                failureCount += 1
                debugLog(logger, "[SideBackup] Backup: Skipping '\(lastComponent)' — destination re-appeared during copy (516): \(copyError.localizedDescription)")
                continue
            } catch {
                // Ignore errors for /Documents/Inbox
                guard !(fileURL.lastPathComponent == "Inbox" && fileURL.deletingLastPathComponent().lastPathComponent == "Documents") else {
                    debugLog(logger, "[SideBackup] Failed to copy Inbox directory: \(error)")
                    continue
                }
                if skipNonCopyable {
                    failureCount += 1
                    debugLog(logger, "[SideBackup] Backup: Skipping non-copyable '\(lastComponent)' — \(error.localizedDescription)")
                    continue
                }
                failureCount += 1
                throw error
            }
        }
        
        debugLog(logger, "[SideBackup] Copied '\(sourceDirectoryURL.lastPathComponent)' directory — \(successCount) succeeded, \(failureCount) failed/skipped, \(contents.count) total.")
    }
    
    @discardableResult
    func removeItemRetrying(at url: URL, isDirectory: Bool, fallbackMerge: (() throws -> Void)? = nil, maxAttempts: Int = 3, logger: ConsoleLog) throws -> Bool {
        for attempt in 1...maxAttempts {
            do {
                try self.removeItem(at: url)
                return false
            } catch let error where isDirectory && (isLockingError(error) || (error as NSError).code == CocoaError.fileWriteNoPermission.rawValue) {
                // Cannot delete the directory itself — merge its contents recursively instead
                try fallbackMerge?()
                return true
            } catch let error where isLockingError(error) {
                debugLog(logger, "[SideBackup] Backup: Remove attempt \(attempt)/\(maxAttempts) for '\(url.lastPathComponent)' failed — \(error.localizedDescription)")
                if attempt < maxAttempts { Thread.sleep(forTimeInterval: 0.2) }
                else { throw error }
            }
        }
        return false
    }
    
    func copyItemRetrying(from sourceURL: URL, to destinationURL: URL, skipNonCopyable: Bool = false, maxAttempts: Int = 3, logger: ConsoleLog) throws {
        for attempt in 1...maxAttempts {
            do {
                try self.copyItem(at: sourceURL, to: destinationURL)
                verboseLog(logger, "[SideBackup] Copied item from \(sourceURL) to \(destinationURL)")
                return
            } catch let error where isLockingError(error) {
                verboseLog(logger, "[SideBackup] Backup: Copy attempt \(attempt)/\(maxAttempts) for '\(sourceURL.lastPathComponent)' failed — \(error.localizedDescription)")
                if attempt < maxAttempts { Thread.sleep(forTimeInterval: 0.2) }
                else if skipNonCopyable {
                    debugLog(logger, "[SideBackup] Backup: Skipping non-copyable '\(sourceURL.lastPathComponent)' after \(maxAttempts) attempts — \(error.localizedDescription)")
                    return
                }
                else { throw error }
            } catch let error where isFileExistsError(error) {
                verboseLog(logger, "[SideBackup] Backup: Destination already exists during copy for '\(destinationURL.lastPathComponent)'. Attempting to remove existing item and retry...")
                do {
                    try self.removeItem(at: destinationURL)
                } catch {
                    verboseLog(logger, "[SideBackup] Backup: Failed to remove conflicting item at \(destinationURL) on attempt \(attempt): \(error.localizedDescription)")
                }
            }
        }
    }
    
    // Returns 'true' if the error is a transient OS-level locking error (item in use by SpringBoard, kernel, etc.).
    func isLockingError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return nsError.code == CocoaError.fileWriteNoPermission.rawValue || nsError.code == CocoaError.fileReadNoPermission.rawValue
        }
        if nsError.domain == NSPOSIXErrorDomain {
            return nsError.code == Int(POSIXError.EPERM.rawValue) ||
                   nsError.code == Int(POSIXError.EACCES.rawValue) ||
                   nsError.code == Int(POSIXError.EBUSY.rawValue)
        }
        return false
    }
    
    func isFileExistsError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.fileWriteFileExists.rawValue
    }
}
