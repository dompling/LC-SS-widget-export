//
//  ConsoleLog.swift
//  SideBackup
//
//  Created by Magesh K on 2/7/26.
//  Copyright © 2026 SideStore. All rights reserved.

import Foundation
import OSLog

enum SideBackupError: LocalizedError {
    case appGroupNotConfigured(expected: String)
    case appGroupContainerUnresolvable(group: String)

    var errorDescription: String? {
        switch self {
        case .appGroupNotConfigured(let expected):
            return "App Group is not configured. Bundle has no AppGroups entitlement containing '\(expected)'. " +
                   "SideBackup was likely not resigned with the SideStore App Group entitlement."
        case .appGroupContainerUnresolvable(let group):
            return "Could not resolve container URL for App Group '\(group)'. " +
                   "The provisioning profile may be missing the App Group entitlement."
        }
    }
}


final class ConsoleLog: Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var _isVerbose: Bool = false

    static var isVerbose: Bool {
        lock.withLock { _isVerbose }
    }
    static func setVerbose(_ state: Bool){
        lock.withLock { _isVerbose = state }
    }

    private static let sharedResult: Result<ConsoleLog, Error> = Result {
        try ConsoleLog()
    }

    static func getConsoleLog() throws -> ConsoleLog {
        try sharedResult.get()
    }

    static var bootCheckError: SideBackupError? {
        do {
            _ = try getConsoleLog()
            return nil
        } catch let error as SideBackupError {
            return error
        } catch {
            let group = Bundle.main.altstoreAppGroup ?? "(nil)"
            return .appGroupContainerUnresolvable(group: group)
        }
    }

    private let logger = Logger(subsystem: "io.sidestore.SideBackup", category: "General")
    private let logFileURL: URL

    private init() throws {
        self.logFileURL = try Self.determineLogFileURL()

        // Auto-clear the log file on first initialization of the singleton
        try "".write(to: self.logFileURL, atomically: true, encoding: .utf8)
    }

    private static func determineLogFileURL() throws -> URL {
        guard let appGroup = Bundle.main.altstoreAppGroup else {
            throw SideBackupError.appGroupNotConfigured(expected: Bundle.baseAltStoreAppGroupID)
        }
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            throw SideBackupError.appGroupContainerUnresolvable(group: appGroup)
        }
        let logsDir = containerURL.appendingPathComponent("Logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        return logsDir.appendingPathComponent("SideBackup.log")
    }

    func log(_ message: String, terminator: String = "\n") {
        // 1. Log to Apple's OSLog
        logger.info("\(message)")

        // 2. Append to shared file in App Group
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            if let data = (message + terminator).data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
        } else {
            // Create file if it doesn't exist
            try? (message + terminator).write(to: logFileURL, atomically: true, encoding: .utf8)
        }
    }
}

private func getTag(level: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    let timestamp = formatter.string(from: Date())
    return "\(timestamp) \(level): "
}

// Global print override to shadow Swift's standard print
func debugLog(_ logger: ConsoleLog, _ items: Any..., separator: String = " ", terminator: String = "\n") {
    let message = items.map { "\($0)" }.joined(separator: separator)
    if !message.isEmpty && message.allSatisfy({ $0 == "\n" || $0 == "\r" }) {
        logger.log(message, terminator: "")
    } else {
        logger.log("\(getTag(level: "[D]"))\(message)", terminator: terminator)
    }
}

func verboseLog(_ logger: ConsoleLog, _ items: Any..., separator: String = " ", terminator: String = "\n") {
    guard ConsoleLog.isVerbose else { return }
    let message = items.map { "\($0)" }.joined(separator: separator)
    if !message.isEmpty && message.allSatisfy({ $0 == "\n" || $0 == "\r" }) {
        logger.log(message, terminator: "")
    } else {
        logger.log("\(getTag(level: "[V]"))\(message)", terminator: terminator)
    }
}
