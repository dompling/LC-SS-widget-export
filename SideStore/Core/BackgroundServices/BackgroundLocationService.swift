//
//  BackgroundLocationService.swift
//  SideStore
//
//  Created by Magesh K on 15/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import CoreLocation

public final class BackgroundLocationService: BackgroundService, @unchecked Sendable {
    public static let shared = BackgroundLocationService()

    public var isRunning: Bool {
        runningState
    }

    private let manager: CLLocationManager
    private let delegateBridge: LocationDelegateBridge
    private var runningState = false
    private let lock = NSLock()

    public init() {
        let bridge = LocationDelegateBridge()
        self.delegateBridge = bridge
        self.manager = CLLocationManager()
        self.manager.delegate = bridge
        self.manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        self.manager.distanceFilter = 4
        self.manager.allowsBackgroundLocationUpdates = true
        self.manager.pausesLocationUpdatesAutomatically = false
        self.manager.showsBackgroundLocationIndicator = false

        bridge.onAuthorizationChange = { [weak self] status in
            guard let self else { return }
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                if self.runningState && 
                   UserDefaults.standard.isBackgroundServiceEnabled && 
                   UserDefaults.standard.backgroundServiceMode == .location 
                {
                    self.startLocationUpdates()
                }
            }
        }
    }

    @discardableResult
    public func start() -> Bool {
        BackgroundAudioService.shared.stop()

        lock.lock()
        defer { lock.unlock() }

        runningState = true
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestAlwaysAuthorization()
        } else if status == .authorizedAlways || status == .authorizedWhenInUse {
            startLocationUpdates()
        }
        return true
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        runningState = false
        manager.stopUpdatingLocation()
    }

    public func prepare() async -> Bool {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestAlwaysAuthorization()
        }
        return status != .denied && status != .restricted
    }

    private func startLocationUpdates() {
        manager.startUpdatingLocation()
    }
}

private final class LocationDelegateBridge: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    var onAuthorizationChange: (@Sendable (CLAuthorizationStatus) -> Void)?

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        onAuthorizationChange?(status)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // we don't care
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // we don't care
    }
}
