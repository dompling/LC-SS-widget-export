//
//  FileOutputStream.swift
//  SideStore
//
//  Created by Magesh K on 28/12/24.
//  Copyright © 2024 SideStore. All rights reserved.
//

import Foundation
import QuartzCore

public class FileOutputStream: OutputStream {
    public var fileHandleProvider: (() -> FileHandle?)?
    public var fileExistsProvider: (() -> Bool)?
    
    private var fileHandle: FileHandle?
    private var lastFailureTime: Date?
    private var lastExistsCheckTime: Double = 0
    
    public init(fileHandle: FileHandle, fileHandleProvider: @escaping () -> FileHandle?, fileExistsProvider: @escaping () -> Bool) {
        self.fileHandle = fileHandle
        self.fileHandleProvider = fileHandleProvider
        self.fileExistsProvider = fileExistsProvider
    }
    
    public func write(_ data: Data) {
        do {
            // Check if the file still exists on disk, but rate-limited to at most once every 1.0 second using high-perf clock
            let now = CACurrentMediaTime()
            if now - lastExistsCheckTime >= 1.0 {
                lastExistsCheckTime = now
                if let existsProvider = fileExistsProvider, !existsProvider() {
                    // File was deleted! Clear handle to trigger recreate.
                    self.fileHandle = nil
                }
            }
            
            try self.ensureFileHandle()
            
            guard let fileHandle = self.fileHandle else { return }
            
            try fileHandle.write(contentsOf: data)
            
            // A successful write resets the failure cooldown
            lastFailureTime = nil
        } catch {
            self.fileHandle = nil
            
            let now = Date()
            if let lastFail = lastFailureTime, now.timeIntervalSince(lastFail) < 10.0 {
                // Within 10-second cooldown window, skip retry
                self.logErrorToStderr("FileOutputStream: Write failed. Cooldown active. Skipping recreation.")
                return
            }
            
            // Try to recreate exactly once
            if let provider = fileHandleProvider, let newHandle = provider() {
                self.fileHandle = newHandle
                lastFailureTime = nil
                
                do {
                    try newHandle.write(contentsOf: data)
                } catch {
                    self.fileHandle = nil
                    lastFailureTime = Date() // Record failing point
                    self.logErrorToStderr("FileOutputStream: Re-created file handle but writing still failed: \(error.localizedDescription)")
                }
            } else {
                lastFailureTime = Date() // Record failing point
                self.logErrorToStderr("FileOutputStream: Failed to re-create file handle via provider.")
            }
        }
    }
    
    private func ensureFileHandle() throws {
        if fileHandle == nil {
            let now = Date()
            if let lastFail = lastFailureTime, now.timeIntervalSince(lastFail) < 10.0 {
                throw NSError(domain: "FileOutputStream", code: 1, userInfo: [NSLocalizedDescriptionKey: "Within 10-second cooldown window"])
            }
            
            if let provider = fileHandleProvider, let newHandle = provider() {
                self.fileHandle = newHandle
                lastFailureTime = nil
            } else {
                lastFailureTime = Date()
                throw NSError(domain: "FileOutputStream", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to recreate file handle via provider"])
            }
        }
    }
    
    private func logErrorToStderr(_ message: String) {
        let errorMsg = message + "\n"
        if let errorData = errorMsg.data(using: .utf8) {
            errorData.withUnsafeBytes { rawBuffer in
                if let base = rawBuffer.baseAddress {
                    _ = Darwin.write(STDERR_FILENO, base, errorData.count)
                }
            }
        }
    }
    
    public func flush() {
        try? fileHandle?.synchronize()
    }
    
    public func close() {
        try? fileHandle?.close()
        fileHandle = nil
    }
}
