//
//  OutputStream.swift
//  SideStore
//
//  Created by Magesh K on 28/12/24.
//  Copyright © 2024 SideStore. All rights reserved.
//

import Foundation
import os.log

public protocol OutputStream {
    func write(_ data: Data)
    func flush()
    func close()
}

// NOTE: We cannot use standard NSLog here.
// NSLog writes its output directly to stderr (file descriptor 2). Since ConsoleLogger captures
// stderr, calling NSLog here would write back to the capture pipe, triggering the readability
// handler recursively and leading to an infinite logging loop or a deadlock.
// Apple's os_log writes directly to the logging daemon (bypassing file descriptors) so it is safe to use.
public class SyslogOutputStream: OutputStream {
    private let log = OSLog(subsystem: Bundle.Info.activeBundleIdentifier, category: "console")
    
    public init() {}
    
    public func write(_ data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return }
        let cleanString = string.trimmingCharacters(in: .newlines)
        guard !cleanString.isEmpty else { return }
        
        // Log to system log using Apple's safe, native os_log API
        os_log("%@", log: log, type: .default, cleanString)
    }
    
    public func flush() {}
    public func close() {}
}

public class CompositeOutputStream: OutputStream {
    private let streams: [OutputStream]
    
    public init(_ streams: [OutputStream]) {
        self.streams = streams
    }
    
    public func write(_ data: Data) {
        for stream in streams {
            stream.write(data)
        }
    }
    
    public func flush() {
        for stream in streams {
            stream.flush()
        }
    }
    
    public func close() {
        for stream in streams {
            stream.close()
        }
    }
}
