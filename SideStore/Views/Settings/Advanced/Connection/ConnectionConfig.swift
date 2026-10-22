//
//  ConnectionConfig.swift
//  SideStore
//
//  Created by Magesh K on 02/03/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import Combine

final class ConnectionConfig: ObservableObject {
    static let shared = ConnectionConfig()

    // yeah we dont use default coz we expect auto discovery to find it
    private static var defaultOverrideIP: String { "" }     
    private static var defaultRemoteServerIP: String { AppConstants.Connection.defaultRemoteServerIP }
    private static var defaultWireGuardServerHost: String { AppConstants.Proxy.address }
    private static var defaultWireGuardServerPort: UInt16 { AppConstants.Proxy.defaultPort }

    @Published var tunnelIfaceIp: String?
    @Published var tunnelIfaceSubnetMask: String?
    @Published var tunnelPeerIp: String?
    @Published var tunnelPeerSubnetMask: String?
    @Published var tunnelPeerReachable: Bool = false
    @Published var overrideTunnelPeerIp: String = overrideIPStorage {
        didSet { Self.overrideIPStorage = overrideTunnelPeerIp }
    }
    @Published var overrideTunnelPeerReachable: Bool = false

    @Published var remoteServerIp: String = remoteServerIPStorage {
        didSet { Self.remoteServerIPStorage = remoteServerIp }
    }
    @Published var remotePeerIp: String?
    @Published var remoteReachable: Bool = false

    @Published var useLocalVPN: Bool = useLocalVPNStorage {
        didSet { Self.useLocalVPNStorage = useLocalVPN }
    }

    @Published var wireguardServerHost: String = wireguardServerHostStorage {
        didSet { Self.wireguardServerHostStorage = wireguardServerHost }
    }

    @Published var wireguardServerPort: UInt16 = wireguardServerPortStorage {
        didSet { Self.wireguardServerPortStorage = wireguardServerPort }
    }

    private static var overrideIPStorage: String {
        get { UserDefaults.standard.tunnelOverridePeerIp ?? defaultOverrideIP }
        set { UserDefaults.standard.tunnelOverridePeerIp = newValue }
    }

    private static var remoteServerIPStorage: String {
        get { UserDefaults.standard.remoteServerIp ?? defaultRemoteServerIP }
        set { UserDefaults.standard.remoteServerIp = newValue }
    }

    private static var useLocalVPNStorage: Bool {
        get { UserDefaults.standard.useLocalVPN }
        set { UserDefaults.standard.useLocalVPN = newValue }
    }

    private static var wireguardServerHostStorage: String {
        get { UserDefaults.standard.wireGuardServerHost ?? defaultWireGuardServerHost }
        set { UserDefaults.standard.wireGuardServerHost = newValue }
    }

    private static var wireguardServerPortStorage: UInt16 {
        get { UserDefaults.standard.wireGuardServerPort ?? defaultWireGuardServerPort }
        set { UserDefaults.standard.wireGuardServerPort = newValue }
    }

    var tunnelPeerActive: ActiveState { tunnelPeerReachable ? .yes : .no }
    var overrideTunnelPeerActive: ActiveState { overrideTunnelPeerReachable ? .yes : .no }
    var remoteActive: ActiveState { remoteReachable ? .yes : .no }

    var formattedTunnelIface: String? {
        guard let ip = tunnelIfaceIp, !ip.isEmpty else { return nil }
        if let mask = tunnelIfaceSubnetMask, let cidr = Self.cidrPrefix(from: mask) {
            return "\(ip)/\(cidr)"
        }
        return ip
    }

    var formattedTunnelPeer: String? {
        guard let ip = tunnelPeerIp, !ip.isEmpty else { return nil }
        if let mask = tunnelPeerSubnetMask, let cidr = Self.cidrPrefix(from: mask) {
            return "\(ip)/\(cidr)"
        }
        return ip
    }

    static func cidrPrefix(from subnetMask: String) -> Int? {
        let octets = subnetMask.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return nil }
        return octets.reduce(0) { $0 + $1.nonzeroBitCount }
    }
}

extension UserDefaults {
    @objc var tunnelOverridePeerIp: String? {
        get { self.string(forKey: "TunnelOverridePeerIp") }
        set { self.set(newValue, forKey: "TunnelOverridePeerIp") }
    }

    @objc var remoteServerIp: String? {
        get { self.string(forKey: "RemoteServerIp") }
        set { self.set(newValue, forKey: "RemoteServerIp") }
    }

    @objc var wireGuardServerHost: String? {
        get { self.string(forKey: "WireGuardServerHost") }
        set { self.set(newValue, forKey: "WireGuardServerHost") }
    }

    var wireGuardServerPort: UInt16? {
        get {
            guard self.object(forKey: "WireGuardServerPort") != nil else { return nil }
            let val = self._wireGuardServerPort
            return (val > 0 && val <= 65535) ? UInt16(val) : nil
        }
        set {
            if let newValue {
                self._wireGuardServerPort = Int(newValue)
            } else {
                self.removeObject(forKey: "WireGuardServerPort")
            }
        }
    }

    @objc(wireGuardServerPort) private var _wireGuardServerPort: Int {
        get { self.integer(forKey: "WireGuardServerPort") }
        set { self.set(newValue, forKey: "WireGuardServerPort") }
    }
}
