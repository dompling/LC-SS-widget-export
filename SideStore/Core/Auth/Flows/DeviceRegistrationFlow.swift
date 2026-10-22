//
//  DeviceRegistrationFlow.swift
//  SideStore
//
//  Created by Magesh K on 13/09/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
import SideSign
import Minimuxer

protocol DeviceProvisioningHandler: AnyObject, Sendable {
    func resolveDeviceRegistrationErrors(_ error: Error) async -> ProvisioningErrorDecision
}

final class DeviceRegistrationFlow: @unchecked Sendable {
    weak var handler: DeviceProvisioningHandler?
    
    init(handler: DeviceProvisioningHandler? = nil) {
        self.handler = handler
    }

    @discardableResult
    func registerCurrentDevice(for team: ALTTeam) async throws -> ALTDevice? {
        while true {
            do {
                return try await self.performDeviceRegistration(for: team)
            } catch {
                if let handler = self.handler {
                    let decision = await handler.resolveDeviceRegistrationErrors(error)
                    switch decision {
                    case .retry:
                        continue
                    case .skip:
                        return nil
                    case .cancel:
                        throw OperationError.cancelled
                    }
                } else {
                    throw error
                }
            }
        }
    }
    
    private func fetchDeviceUDID() async throws -> String {
        let isCellularEnabled = CellularRefreshManager.shared.isEnabled
        if isCellularEnabled {
            await CellularRefreshManager.shared.turnOffDataIfNeeded()
        }
        
        do {
            let udid = try await safeFetchUDID()
            
            if isCellularEnabled {
                await CellularRefreshManager.shared.turnOnDataIfNeeded(addOnDelay: 2.0)
            }
            return udid
        } catch {
            if isCellularEnabled {
                await CellularRefreshManager.shared.turnOnDataIfNeeded(addOnDelay: 2.0)
            }
            throw error
        }
    }

    private func performDeviceRegistration(for team: ALTTeam) async throws -> ALTDevice {
        debugLog("[DeviceRegistrationFlow] performDeviceRegistration starting...")
        let udid = try await self.fetchDeviceUDID()
        debugLog("[DeviceRegistrationFlow] Fetched device UDID: \(udid). Fetching team devices...")
        
        let devices = try await DeveloperPortalProxy.shared.fetchDevices(for: team, types: .all)
        if let device = devices.first(where: { $0.identifier.caseInsensitiveCompare(udid) == .orderedSame }) {
            debugLog("[DeviceRegistrationFlow] Device '\(device.name)' (UDID: \(udid)) is registered on team.")
            UserDefaults.standard.isDeviceRegistered = true
            return device
        } else {
            let deviceName = await MainActor.run { UIDevice.current.name }
            debugLog("[DeviceRegistrationFlow] Registering new device '\(deviceName)' (UDID: \(udid))...")
            let device = try await DeveloperPortalProxy.shared.registerDevice(name: deviceName, identifier: udid, type: DeveloperPortalProxy.currentDeviceType, team: team)
            debugLog("[DeviceRegistrationFlow] Device '\(device.name)' (UDID: \(udid)) successfully registered.")
            UserDefaults.standard.isDeviceRegistered = true
            return device
        }
    }
}
