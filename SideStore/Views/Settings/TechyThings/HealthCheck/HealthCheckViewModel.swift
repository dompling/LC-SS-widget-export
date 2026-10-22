//
//  HealthCheckViewModel.swift
//  SideStore
//
//  Created by Magesh K on 11/07/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import Minimuxer
import Combine

/*
 Minimuxer.shared().isReady Result Mapping to Core Requirements Statuses:
 
 | Ready Result Case                        | Network   | VPN       | IPSec     | Ping      | Pairing   | DDI       |
 | ---------------------------------------- | --------- | --------- | --------- | --------- | --------- | --------- |
 | .success                                 | Satisfied | Satisfied | Satisfied | Satisfied | Satisfied | Satisfied |
 | .failure(.noConnection)                  | Failed    | Unknown   | Unknown   | Unknown   | Unknown   | Unknown   |
 | .failure(.noVPN) / .failure(.invalidVPN) | Satisfied | Failed    | Unknown   | Unknown   | Unknown   | Unknown   |
 | .failure(.pairingFile)                   | Satisfied | Satisfied | Satisfied | Satisfied | Failed    | Unknown   |
 | .failure(.invalidPairing)                | Satisfied | Satisfied | Satisfied | Satisfied | Failed    | Unknown   |
 | .failure(.mount)                         | Satisfied | Satisfied | Satisfied | Satisfied | Satisfied | Failed    |
 | .failure(.muxerNotListening)             | Satisfied | Satisfied | Satisfied | Satisfied | Satisfied | Satisfied |
 */

@MainActor
final class HealthCheckViewModel: ObservableObject {
    @Published var isWifiSatisfied = false
    @Published var isWiredSatisfied = false
    @Published var isUsbSatisfied = false
    @Published var isBridgeSatisfied = false
    @Published var connectionMode: DeviceConnectionMode = .localVPN
    @Published var isUTunAvailable = false
    @Published var isIKEv2IPSecAvailable = false
    
    @Published var tunnelIfaceIp: String? = nil
    @Published var tunnelIfaceSubnetMask: String? = nil
    @Published var tunnelPeerIp: String? = nil
    @Published var overrideTunnelPeerIp: String = ""
    @Published var overrideTunnelPeerEffective = false
    @Published var remoteServerIp: String = ""
    @Published var remotePeerIp: String? = nil
    @Published var remoteReachable = false
    
    @Published var activeProtocol = ""
    @Published var isPingSuccessful = false
    
    @Published var isDDIMounted = false
    @Published var isPairingFileVerified = false
    @Published var isRPPairing = false
    @Published var isPairingFileLoaded = false
    
    @Published var networkSatisfied: Bool? = nil
    @Published var vpnSatisfied: Bool? = nil
    @Published var ipsecSatisfied: Bool? = nil
    @Published var pingSatisfied: Bool? = nil
    @Published var pairingSatisfied: Bool? = nil
    @Published var ddiSatisfied: Bool? = nil
    
    @Published var minimuxerReadyResult: Result<Bool, MinimuxerError>? = nil
    @Published var availableInterfaces: [LocalInterfaceInfo] = []

    struct HealthCheckMetrics {
        let connectionMode: DeviceConnectionMode
        let wifi: Bool
        let wired: Bool
        let usb: Bool
        let bridge: Bool
        let utun: Bool
        let ipsec: Bool
        let tunnelIfaceIp: String?
        let tunnelIfaceSubnetMask: String?
        let tunnelPeerIp: String?
        let overrideTunnelPeerIp: String?
        let overrideTunnelPeerEffective: Bool
        let remoteServerIp: String
        let remotePeerIp: String?
        let remoteReachable: Bool
        let protocolStr: String
        let pingSuccess: Bool
        let ddi: Bool
        let pairingVerified: Bool
        let isRpPairing: Bool
        let isPairingLoaded: Bool
        let readyResult: Result<Bool, MinimuxerError>
        let scanned: [LocalInterfaceInfo]
    }

    nonisolated private func fetchMetrics() async -> HealthCheckMetrics {
        let mode = await minimuxer.core.getConnectionMode()
        let wifi = minimuxer.network.isWifiSatisfied
        let wired = minimuxer.network.isWiredSatisfied
        let usb = minimuxer.network.isUsbSatisfied
        let bridge = minimuxer.network.isBridgeSatisfied
        let utun = minimuxer.network.isUTunAvailable
        let ipsec = minimuxer.network.isIKEv2IPSecAvailable
        
        let tunnelIfaceIp = ConnectionConfig.shared.formattedTunnelIface
        let tunnelIfaceSubnetMask = ConnectionConfig.shared.tunnelIfaceSubnetMask
        let tunnelPeerIp = ConnectionConfig.shared.formattedTunnelPeer
        let overrideTunnelPeerIp = ConnectionConfig.shared.overrideTunnelPeerIp
        let overrideTunnelPeerEffective = ConnectionConfig.shared.overrideTunnelPeerReachable
        let remoteServerIp = ConnectionConfig.shared.remoteServerIp
        let remotePeerIp = ConnectionConfig.shared.remotePeerIp
        let remoteReachable = ConnectionConfig.shared.remoteReachable
        
        let pairingType = minimuxer.core.pairingFileType
        let protocolStr: String
        switch pairingType {
        case .rppairing:
            protocolStr = "Remote Pairing"
        case .lockdown:
            protocolStr = "Lockdown"
        case .unknown:
            protocolStr = "Unknown"
        }
        
        let targetIp = mode == .localVPN ? (overrideTunnelPeerEffective ? overrideTunnelPeerIp : (ConnectionConfig.shared.tunnelPeerIp ?? "")) : remoteServerIp
        let pingSuccess = !targetIp.isEmpty && minimuxer.core.testDeviceConnection(ifaddr: targetIp)
        
        let ddi = (try? await minimuxer.core.isDDIMounted()) ?? false
        let pairingVerified = (try? await fetchUDID(forceLive: true)) != nil
        let isRpPairing = minimuxer.core.pairingFileType == .rppairing
        let isPairingLoaded = minimuxer.core.isPairingFileLoaded
        let readyResult = await minimuxer.core.isReady(withDDIMountCheck: true)
        let scanned = minimuxer.network.activeInterfaces
        
        return HealthCheckMetrics(
            connectionMode: mode,
            wifi: wifi, wired: wired, usb: usb, bridge: bridge, utun: utun, ipsec: ipsec,
            tunnelIfaceIp: tunnelIfaceIp, tunnelIfaceSubnetMask: tunnelIfaceSubnetMask, tunnelPeerIp: tunnelPeerIp,
            overrideTunnelPeerIp: overrideTunnelPeerIp, overrideTunnelPeerEffective: overrideTunnelPeerEffective,
            remoteServerIp: remoteServerIp, remotePeerIp: remotePeerIp, remoteReachable: remoteReachable,
            protocolStr: protocolStr, pingSuccess: pingSuccess,
            ddi: ddi, pairingVerified: pairingVerified, isRpPairing: isRpPairing, isPairingLoaded: isPairingLoaded,
            readyResult: readyResult, scanned: scanned
        )
    }

    func observeMetrics() async {
        // Perform initial diagnostics load
        let initialMetrics = await self.fetchMetrics()
        let initialStatus = self.computeStatuses(initialMetrics)
        self.updateUI(metrics: initialMetrics, status: initialStatus)
        
        await withTaskGroup(of: Void.self) { group in
            // Immediate Network & Interface Updates (Wi-Fi, interfaces, VPN tunnel presence)
            group.addTask {
                for await _ in minimuxer.network.pathPublisher.values {
                    guard !Task.isCancelled else { break }
                    await self.updateNetworkState()
                }
            }

            // Minimuxer Readiness Updates (Ping, DDI mount, Pairing verification, Muxer status)
            group.addTask {
                for await _ in minimuxerStatusPublisher.values {
                    guard !Task.isCancelled else { break }
                    let metrics = await self.fetchMetrics()
                    let status = self.computeStatuses(metrics)
                    await self.updateUI(metrics: metrics, status: status)
                }
            }
        }
    }

    @MainActor
    private func updateNetworkState() {
        let network = minimuxer.network
        self.isWifiSatisfied = network.isWifiSatisfied
        self.isWiredSatisfied = network.isWiredSatisfied
        self.isUsbSatisfied = network.isUsbSatisfied
        self.isBridgeSatisfied = network.isBridgeSatisfied
        self.isUTunAvailable = network.isUTunAvailable
        self.isIKEv2IPSecAvailable = network.isIKEv2IPSecAvailable
        self.availableInterfaces = network.activeInterfaces
        self.networkSatisfied = network.isWifiSatisfied
        if self.connectionMode == .localVPN {
            self.vpnSatisfied = network.isUTunAvailable
            if !self.isRPPairing {
                self.ipsecSatisfied = network.isIKEv2IPSecAvailable
            }
        }
    }
    
    typealias CoreRequirementStatuses = (
        netSat: Bool?,
        vpnSat: Bool?,
        ipsecSat: Bool?,
        pingSat: Bool?,
        pairingSat: Bool?,
        ddiSat: Bool?
    )

    nonisolated private func computeStatuses(
        _ m: HealthCheckMetrics
    ) -> CoreRequirementStatuses {
        let netSat = m.wifi
        let vpnSat = m.utun
        let isRp = m.protocolStr == "Remote Pairing"
        let ipsecSat = isRp ? nil : m.ipsec

        switch m.readyResult {
        case .success:
            let pingSat = m.pingSuccess
            let isPairingLoaded = minimuxer.core.isPairingFileLoaded
            let pairingSat: Bool? = m.pairingVerified ? true : (isPairingLoaded ? nil : false)
            let ddiSat = m.ddi
            return (netSat, vpnSat, ipsecSat, pingSat, pairingSat, ddiSat)

        case .failure(let error):
            var pingSat: Bool? = m.pingSuccess
            let isPairingLoaded = minimuxer.core.isPairingFileLoaded
            var pairingSat: Bool? = m.pairingVerified ? true : (isPairingLoaded ? nil : false)
            var ddiSat: Bool? = m.ddi

            switch error {
            case .noConnection:
                return (false, nil, nil, nil, nil, nil)
            case .notStarted, .pairingNotLoaded:
                return (nil, nil, nil, nil, nil, nil)
            case .noVPN, .invalidVPN:
                return (netSat, false, nil, nil, nil, nil)
            case .noDevice, .notReachable:
                pingSat = false
                pairingSat = nil
                ddiSat = nil
            case .invalidPairing:
                pairingSat = false
                ddiSat = nil
            case .mount:
                ddiSat = false
            case .muxerNotListening:
                break
            default:
                break
            }

            return (netSat, vpnSat, ipsecSat, pingSat, pairingSat, ddiSat)
        }
    }
    
    @MainActor
    func updateUI(metrics: HealthCheckMetrics, status: CoreRequirementStatuses) {
        self.connectionMode = metrics.connectionMode
        self.isWifiSatisfied = metrics.wifi
        self.isWiredSatisfied = metrics.wired
        self.isUsbSatisfied = metrics.usb
        self.isBridgeSatisfied = metrics.bridge
        self.isUTunAvailable = metrics.utun
        self.isIKEv2IPSecAvailable = metrics.ipsec
        
        self.tunnelIfaceIp = metrics.tunnelIfaceIp
        self.tunnelIfaceSubnetMask = metrics.tunnelIfaceSubnetMask
        self.tunnelPeerIp = metrics.tunnelPeerIp
        self.overrideTunnelPeerIp = metrics.overrideTunnelPeerIp ?? "N/A"
        self.overrideTunnelPeerEffective = metrics.overrideTunnelPeerEffective
        self.remoteServerIp = metrics.remoteServerIp
        self.remotePeerIp = metrics.remotePeerIp
        self.remoteReachable = metrics.remoteReachable
        
        self.activeProtocol = metrics.protocolStr
        self.isPingSuccessful = metrics.pingSuccess
        
        self.isDDIMounted = metrics.ddi
        self.isPairingFileVerified = metrics.pairingVerified
        self.isRPPairing = metrics.isRpPairing
        self.isPairingFileLoaded = metrics.isPairingLoaded
        
        self.networkSatisfied = status.netSat
        self.vpnSatisfied = status.vpnSat
        self.ipsecSatisfied = status.ipsecSat
        self.pingSatisfied = status.pingSat
        self.pairingSatisfied = status.pairingSat
        self.ddiSatisfied = status.ddiSat
        
        self.minimuxerReadyResult = metrics.readyResult
        self.availableInterfaces = metrics.scanned
    }
}
