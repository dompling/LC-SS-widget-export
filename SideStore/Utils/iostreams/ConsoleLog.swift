//
//  ConsoleLog.swift
//  SideStore
//
//  Created by Magesh K on 25/11/24.
//  Copyright © 2024 SideStore. All rights reserved.
//
//

import Foundation

public enum SuffixFormat: String {
    case none
    case timestamp
}

public enum UpdatePolicy {
    case immediate
    case subsequent
}

public struct LogNameInfo {
    public let name: String
    public let suffix: String
    public let fileExtension: String
    
    public var fileName: String {
        return name + suffix + fileExtension
    }
}

class ConsoleLog {
    private static let CONSOLE_LOGS_DIRECTORY = "ConsoleLogs"
    private static let CONSOLE_LOG_NAME_PREFIX = "console"
    private static let CONSOLE_LOG_EXTN = ".log"
    
    private var configuredBaseName: String = ConsoleLog.CONSOLE_LOG_NAME_PREFIX
    private var configuredSuffixFormat: SuffixFormat = .timestamp
    
    public private(set) var activeLogInfo: LogNameInfo?
    private var compositeStream: OutputStream?
    
    private lazy var consoleLogger: ConsoleLogger = {
        let logFileHandle = createLogFileHandle()!
        let fileOutputStream = FileOutputStream(
            fileHandle: logFileHandle,
            fileHandleProvider: { [weak self] in
                return self?.createLogFileHandle()
            },
            fileExistsProvider: { [weak self] in
                guard let self = self else { return false }
                return FileManager.default.fileExists(atPath: self.logFileURL.path)
            }
        )
        let syslogOutputStream = SyslogOutputStream()
        let compositeStream = CompositeOutputStream([fileOutputStream, syslogOutputStream])
        self.compositeStream = compositeStream
        
        return UnBufferedConsoleLogger(stream: compositeStream)
    }()
    
    public func formatFileName(baseName: String, suffixFormat: SuffixFormat) -> LogNameInfo {
        let (name, ext) = splitFileName(baseName, defaultExtn: ConsoleLog.CONSOLE_LOG_EXTN)
        switch suffixFormat {
        case .none:
            return LogNameInfo(name: name, suffix: "", fileExtension: ext)
        case .timestamp:
            let currentTime = Date()
            let dateTimeStamp = DateTimeUtil.getDateInTimeStamp(date: currentTime)
            return LogNameInfo(name: name, suffix: "_" + dateTimeStamp, fileExtension: ext)
        }
    }
    
    private func splitFileName(_ fileName: String, defaultExtn: String) -> (name: String, extn: String) {
        let url = URL(fileURLWithPath: fileName)
        let ext = url.pathExtension
        if ext.isEmpty {
            return (fileName, defaultExtn)
        } else {
            return (url.deletingPathExtension().lastPathComponent, "." + ext)
        }
    }
    
    public func updateConfiguration(baseName: String, suffixFormat: SuffixFormat, policy: UpdatePolicy = .subsequent) {
        self.configuredBaseName = baseName
        self.configuredSuffixFormat = suffixFormat
        
        if policy == .immediate {
            let newInfo = formatFileName(baseName: baseName, suffixFormat: suffixFormat)
            self.activeLogInfo = newInfo
            self.compositeStream?.close() // Triggers lazy recreation of the handle on next print/write
        }
    }
    
    private func createLogFileHandle() -> FileHandle? {
        let isRecreation = (activeLogInfo != nil)
        
        if activeLogInfo == nil {
            activeLogInfo = formatFileName(baseName: configuredBaseName, suffixFormat: configuredSuffixFormat)
        }
        let url = logFileURL
        let parentDir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
        }
        let fileExists = FileManager.default.fileExists(atPath: url.path)
        if !fileExists {
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
        }
        let handle = try? FileHandle(forWritingTo: url)
        handle?.seekToEndOfFile()
        
        if !fileExists && isRecreation, let handle = handle {
            let timestamp = DateTimeUtil.getDateInTimeStamp(date: Date())
            let header = """
            
            ===================================================
            [WARNING] Log file was deleted/missing mid-session.
            [WARNING] Recreated log file at: \(timestamp)
            ===================================================
            
            
            """
            if let data = header.data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
        }
        
        return handle
    }
    
    private lazy var consoleLogsDir: URL = {
        // create a directory for console logs
        let docsDir = FileManager.default.documentsDirectory
        let consoleLogsDir = docsDir.appendingPathComponent(ConsoleLog.CONSOLE_LOGS_DIRECTORY)
        if !FileManager.default.fileExists(atPath: consoleLogsDir.path) {
            try! FileManager.default.createDirectory(at: consoleLogsDir, withIntermediateDirectories: true, attributes: nil)
        }
        return consoleLogsDir
    }()
    
    public var logName: String {
        if activeLogInfo == nil {
            activeLogInfo = formatFileName(baseName: configuredBaseName, suffixFormat: configuredSuffixFormat)
        }
        return activeLogInfo?.fileName ?? ""
    }
    
    public var logFileURL: URL {
        if activeLogInfo == nil {
            activeLogInfo = formatFileName(baseName: configuredBaseName, suffixFormat: configuredSuffixFormat)
        }
        return consoleLogsDir.appendingPathComponent(activeLogInfo!.fileName)
    }
    
    func startCapturing() {
        consoleLogger.startCapturing()
    }
    
    func stopCapturing() {
        consoleLogger.stopCapturing()
    }
}

