//
//  CellularRefreshManager.swift
//  SideStore
//
//  Created by Magesh K on 4/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import UIKit
import Minimuxer

public final class CellularRefreshManager: @unchecked Sendable {
    public static let shared = CellularRefreshManager()

    private let lock = NSLock()
    private var cachedDidTurnOffData = false
    private var didTurnOffData: Bool {
        get { lock.withLock { cachedDidTurnOffData } }
        set { lock.withLock { cachedDidTurnOffData = newValue } }
    }

    private init() {}

    public var isSupported: Bool {
        #if os(tvOS)
        return false
        #else
        return true
        #endif
    }

    public var isEnabled: Bool {
        return UserDefaults.standard.isCellularRefreshEnabled
    }

    public var isCellularMode: Bool {
        guard isSupported && isEnabled else { return false }
        return !minimuxer.network.isWifiSatisfied
    }

    public func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.isCellularRefreshEnabled = enabled
    }

    public static func sanitizeShortcutName(_ name: String, fallback: String = "") -> String {
        var sanitized = name.components(separatedBy: .controlCharacters).joined()
        sanitized = sanitized.replacingOccurrences(of: "\n", with: "")
        sanitized = sanitized.replacingOccurrences(of: "\r", with: "")
        sanitized = sanitized.replacingOccurrences(of: "/", with: "")
        sanitized = sanitized.replacingOccurrences(of: ":", with: "")
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.count > 100 {
            sanitized = String(sanitized.prefix(100)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return sanitized.isEmpty ? fallback : sanitized
    }

    public var turnOffDataShortcutName: String {
        let raw = UserDefaults.standard.turnOffDataShortcutName
        return Self.sanitizeShortcutName(raw, fallback: AppConstants.Shortcuts.defaultTurnOffDataShortcutName)
    }

    public var turnOnDataShortcutName: String {
        let raw = UserDefaults.standard.turnOnDataShortcutName
        return Self.sanitizeShortcutName(raw, fallback: AppConstants.Shortcuts.defaultTurnOnDataShortcutName)
    }

    public func setTurnOffDataShortcutName(_ name: String) {
        let sanitized = Self.sanitizeShortcutName(name, fallback: AppConstants.Shortcuts.defaultTurnOffDataShortcutName)
        UserDefaults.standard.turnOffDataShortcutName = sanitized
    }

    public func setTurnOnDataShortcutName(_ name: String) {
        let sanitized = Self.sanitizeShortcutName(name, fallback: AppConstants.Shortcuts.defaultTurnOnDataShortcutName)
        UserDefaults.standard.turnOnDataShortcutName = sanitized
    }

    public func shortcutURL(for name: String, fallback: String) -> URL {
        let sanitized = Self.sanitizeShortcutName(name, fallback: fallback)
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: sanitized)]
        return components.url ?? URL(string: "shortcuts://run-shortcut?name=\(fallback)")!
    }

    @MainActor
    private func openShortcut(url: URL) async -> Bool {
        debugLog("[CellularRefreshManager] Opening shortcut URL: \(url.absoluteString)")
        let success = await UIApplication.shared.open(url)
        debugLog("[CellularRefreshManager] Shortcut URL open completed with success: \(success)")
        return success
    }

    @discardableResult
    private func turnOffData() async -> Bool {
        let name = turnOffDataShortcutName
        let url = shortcutURL(for: name, fallback: AppConstants.Shortcuts.defaultTurnOffDataShortcutName)
        debugLog("[CellularRefreshManager] Executing TurnOffData shortcut '\(name)' (URL: \(url.absoluteString))...")
        let success = await openShortcut(url: url)
        debugLog("[CellularRefreshManager] TurnOffData shortcut finished execution.")
        return success
    }

    @discardableResult
    private func turnOnData() async -> Bool {
        let name = turnOnDataShortcutName
        let url = shortcutURL(for: name, fallback: AppConstants.Shortcuts.defaultTurnOnDataShortcutName)
        debugLog("[CellularRefreshManager] Executing turnOnData shortcut '\(name)' (URL: \(url.absoluteString))...")
        let success = await openShortcut(url: url)
        debugLog("[CellularRefreshManager] turnOnData shortcut finished execution.")
        return success
    }

    public var turnOffDataBaseDelayOverride: TimeInterval? {
        guard let value = UserDefaults.standard.object(forKey: "turnOffDataBaseDelayOverride") as? Double else {
            return nil
        }
        return max(0, value)
    }

    public var turnOnDataBaseDelayOverride: TimeInterval? {
        guard let value = UserDefaults.standard.object(forKey: "turnOnDataBaseDelayOverride") as? Double else {
            return nil
        }
        return max(0, value)
    }

    public func setTurnOffDataBaseDelayOverride(_ delay: TimeInterval?) {
        if let delay = delay {
            UserDefaults.standard.set(max(0, delay), forKey: "turnOffDataBaseDelayOverride")
        } else {
            UserDefaults.standard.removeObject(forKey: "turnOffDataBaseDelayOverride")
        }
    }

    public func setTurnOnDataBaseDelayOverride(_ delay: TimeInterval?) {
        if let delay = delay {
            UserDefaults.standard.set(max(0, delay), forKey: "turnOnDataBaseDelayOverride")
        } else {
            UserDefaults.standard.removeObject(forKey: "turnOnDataBaseDelayOverride")
        }
    }

    public func resetToDefaults() {
        setTurnOffDataShortcutName(AppConstants.Shortcuts.defaultTurnOffDataShortcutName)
        setTurnOnDataShortcutName(AppConstants.Shortcuts.defaultTurnOnDataShortcutName)
        setTurnOffDataBaseDelayOverride(nil)
        setTurnOnDataBaseDelayOverride(nil)
    }

    private func sleep(baseDelay: TimeInterval, addOnDelay: TimeInterval = 0) async {
        let totalDelay = baseDelay + addOnDelay
        guard totalDelay > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(totalDelay * 1_000_000_000))
    }

    private func waitForMinimuxerReady(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        debugLog("[CellularRefreshManager] Waiting for minimuxer endpoint to become ready (timeout: \(timeout)s)...")
        while Date() < deadline {
            await minimuxer.network.refreshEndpoint()
            if case .success(true) = await minimuxer.core.isReady(withNetworkCheck: false) {
                debugLog("[CellularRefreshManager] Minimuxer is ready.")
                return true
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        debugLog("[CellularRefreshManager] Timed out waiting for minimuxer to become ready.")
        return false
    }

    // public apis
    @discardableResult
    public func turnOffDataIfNeeded(addOnDelay: TimeInterval = 0) async -> Bool {
        guard isSupported && isEnabled else { return false }
        guard !didTurnOffData else { return false }

        // If Wi-Fi is active, skip running cellular toggle shortcuts
        guard !minimuxer.network.isWifiSatisfied else {
            debugLog("[CellularRefreshManager] Wi-Fi is active, skipping turnOff shortcut.")
            return false
        }

        let success = await turnOffData()
        if success {
            didTurnOffData = true
            let effectiveBaseDelay = turnOffDataBaseDelayOverride ?? AppConstants.Shortcuts.defaultTurnOffDataBaseDelay
            await sleep(baseDelay: effectiveBaseDelay, addOnDelay: addOnDelay)
            _ = await waitForMinimuxerReady(timeout: 2.0)
        }
        return success
    }

    @discardableResult
    public func turnOnDataIfNeeded(addOnDelay: TimeInterval = 0) async -> Bool {
        guard didTurnOffData else { return false }

        let success = await turnOnData()
        if success {
            didTurnOffData = false
        }
        let effectiveBaseDelay = turnOnDataBaseDelayOverride ?? AppConstants.Shortcuts.defaultTurnOnDataBaseDelay
        await sleep(baseDelay: effectiveBaseDelay, addOnDelay: addOnDelay)
        return success
    }
}
