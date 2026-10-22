//
//  LocalNetworkPermissionChecker.swift
//  SideStore
//
//  Created by Magesh K on 04/07/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation

@MainActor
final class LocalNetworkPermissionChecker: NSObject {
    static let shared = LocalNetworkPermissionChecker()
    
    private var service: NetService?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var timer: Timer?
    
    private override init() {
        super.init()
    }
    
    /// Checks if Local Network permission is granted by publishing a dummy NetService.
    /// If not determined, this triggers the system permission alert.
    func checkPermission() async -> Bool {
        debugLog("[LocalNetworkCheck] Checking local network permission via NetService publication...")
        
        // If there's an ongoing check, fail it first to avoid hanging
        cleanup(returning: false)
        
        // We use '_altserver._tcp.' which is already defined in Info.plist
        let netService = NetService(domain: "local.", type: "_altserver._tcp.", name: "LocalNetworkPrivacy", port: 1100)
        self.service = netService
        netService.delegate = self
        
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            
            debugLog("[LocalNetworkCheck] Publishing dummy NetService immediately...")
            netService.publish()
            
            var ticks = 0
            
            // Set a timer to check state periodically as a fallback timeout
            self.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    // Only evaluate while active to avoid timing out while the system permission alert is open
                    guard UIApplication.shared.applicationState == .active else {
                        return
                    }
                    
                    ticks += 1
                    if ticks >= 2 {
                        debugLog("[LocalNetworkCheck] Publication timed out. Permission denied.")
                        self.cleanup(returning: false)
                    }
                }
            }
        }
    }
    
    private func cleanup(returning result: Bool) {
        timer?.invalidate()
        timer = nil
        service?.stop()
        service?.delegate = nil
        service = nil
        
        if let continuation = self.continuation {
            self.continuation = nil
            continuation.resume(returning: result)
        }
    }
}

extension LocalNetworkPermissionChecker: NetServiceDelegate {
    
    nonisolated func netServiceDidPublish(_ sender: NetService) {
        Task { @MainActor in
            debugLog("[LocalNetworkCheck] NetService published successfully. Permission granted.")
            self.cleanup(returning: true)
        }
    }
    
    nonisolated func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        Task { @MainActor in
            debugLog("[LocalNetworkCheck] NetService failed to publish: \(errorDict). Permission denied.")
            self.cleanup(returning: false)
        }
    }
}
