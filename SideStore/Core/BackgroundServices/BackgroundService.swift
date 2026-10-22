//
//  BackgroundService.swift
//  SideStore
//
//  Created by Magesh K on 15/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation

public protocol BackgroundService: Sendable {
    var isRunning: Bool { get }
    @discardableResult
    func start() -> Bool
    func stop()
    func prepare() async -> Bool
}

public extension BackgroundService {
    func prepare() async -> Bool { true }
}

public enum BackgroundServiceMode: String, CaseIterable, Sendable {
    case audio
    case location

    public var displayName: String {
        switch self {
        case .audio:
            return "Audio"
        case .location:
            return "Location"
        }
    }

    public var subtitle: String {
        switch self {
        case .audio:
            return "Silent keepalive background audio loop"
        case .location:
            return "Low-power keepalive background location"
        }
    }
}

public final class BackgroundServiceManager: @unchecked Sendable {
    public static var shared: any BackgroundService {
        service(for: UserDefaults.standard.backgroundServiceMode)
    }

    public static func service(for mode: BackgroundServiceMode) -> any BackgroundService {
        switch mode {
        case .audio:
            return BackgroundAudioService.shared
        case .location:
            return BackgroundLocationService.shared
        }
    }

    public static func stop() {
        shared.stop()
    }

    public static func switchTo(mode: BackgroundServiceMode) {
        shared.stop()
        UserDefaults.standard.backgroundServiceMode = mode
        if UserDefaults.standard.isBackgroundServiceEnabled {
            service(for: mode).start()
        }
    }

    public static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.isBackgroundServiceEnabled = enabled
        if enabled {
            _ = ensureBackgroundServicesStarted()
        } else {
            stop()
        }
    }

    @discardableResult
    public static func ensureBackgroundServicesStarted() -> Bool {
        guard UserDefaults.standard.isBackgroundServiceEnabled else {
            stop()
            return false
        }
        if !shared.isRunning {
            return shared.start()
        }
        return true
    }

    private init() {}
}
