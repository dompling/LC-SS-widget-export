//
//  ProfileManager.swift
//  SideStore
//
//  Created by Magesh K on 14/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SideSign
import CoreData

public final class ProfileManager: @unchecked Sendable {
    public static let shared = ProfileManager()

    private let fileManager = FileManager.default
    private let assignedProfilesKey = "assignedAppProvisioningProfiles"

    public var profilesDirectory: URL {
        let url = fileManager.applicationSupportDirectory.appendingPathComponent("ProvisioningProfiles", isDirectory: true)
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
        return url
    }

    private init() {}

    public func getAllLocalProfiles() -> [ALTProvisioningProfile] {
        guard let files = try? fileManager.contentsOfDirectory(at: profilesDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        var profiles: [ALTProvisioningProfile] = []
        for file in files where file.pathExtension.lowercased() == "mobileprovision" {
            if let data = try? Data(contentsOf: file),
               let profile = try? ALTProvisioningProfile(data: data) {
                profiles.append(profile)
            }
        }

        return profiles.sorted { $0.expirationDate > $1.expirationDate }
    }

    public func getProfile(uuid: UUID) -> ALTProvisioningProfile? {
        let fileURL = profilesDirectory.appendingPathComponent("\(uuid.uuidString).mobileprovision")
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let profile = try? ALTProvisioningProfile(data: data) else {
            return nil
        }
        return profile
    }

    public func profileURL(for uuid: UUID) -> URL {
        return profilesDirectory.appendingPathComponent("\(uuid.uuidString).mobileprovision")
    }

    public func getProfile(uuidString: String) -> ALTProvisioningProfile? {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        return getProfile(uuid: uuid)
    }

    @discardableResult
    public func importProfile(from url: URL) throws -> ALTProvisioningProfile {
        let data = try Data(contentsOf: url)
        return try importProfile(data: data)
    }

    @discardableResult
    public func importProfile(data: Data) throws -> ALTProvisioningProfile {
        let profile = try ALTProvisioningProfile(data: data)
        let destinationURL = profilesDirectory.appendingPathComponent("\(profile.uuid.uuidString).mobileprovision")
        try data.write(to: destinationURL, options: .atomic)
        debugLog("[ProfileManager] Imported provisioning profile '\(profile.name)' (\(profile.uuid)) to \(destinationURL.path)")
        return profile
    }

    public func deleteProfile(uuid: UUID) {
        let fileURL = profilesDirectory.appendingPathComponent("\(uuid.uuidString).mobileprovision")
        try? fileManager.removeItem(at: fileURL)

        var assignments = getAssignedProfilesDict()
        let uuidStr = uuid.uuidString
        let matchingKeys = assignments.filter { $0.value == uuidStr }.map { $0.key }
        for key in matchingKeys {
            assignments.removeValue(forKey: key)
        }
        saveAssignedProfilesDict(assignments)
        debugLog("[ProfileManager] Deleted provisioning profile \(uuid)")
    }

    public enum CertificateAnalysisResult: Equatable {
        case signable(certName: String, serialNumber: String)
        case publicOnly(certName: String, serialNumber: String)
        case noMatch(embeddedCount: Int)
    }

    public func analyzeCertificates(for profile: ALTProvisioningProfile) -> CertificateAnalysisResult {
        if let signable = getMatchingCertificate(for: profile) {
            return .signable(certName: signable.name, serialNumber: signable.serialNumber)
        }

        let allX509 = CertificateManager.shared.getAllLocalX509Certificates()
        for profileCert in profile.certificates {
            let profSerial = cleanSerial(profileCert.serialNumber)
            for localX509 in allX509 {
                let localSerial = cleanSerial(localX509.serialNumber)
                if profSerial == localSerial ||
                   (profileCert.data != nil && profileCert.data == localX509.data) {
                    return .publicOnly(certName: localX509.name, serialNumber: localX509.serialNumber)
                }
            }
        }

        return .noMatch(embeddedCount: profile.certificates.count)
    }

    public func getMatchingCertificate(for profile: ALTProvisioningProfile) -> ALTCertificate? {
        let allSignables: [ALTCertificate]
        if let active = CertificateManager.shared.activeCertificate?.certificate {
            var certs = CertificateManager.shared.getAllLocalCertificates()
            if !certs.contains(where: { cleanSerial($0.serialNumber) == cleanSerial(active.serialNumber) }) {
                certs.append(active)
            }
            allSignables = certs
        } else {
            allSignables = CertificateManager.shared.getAllLocalCertificates()
        }

        for profileCert in profile.certificates {
            let profSerial = cleanSerial(profileCert.serialNumber)
            for signable in allSignables {
                let signableSerial = cleanSerial(signable.serialNumber)
                if profSerial == signableSerial {
                    return signable
                }
                if let profData = profileCert.data, let signData = signable.data, profData == signData {
                    return signable
                }
            }
            if let signable = CertificateManager.shared.getSignableCertificate(for: profileCert.serialNumber) {
                return signable
            }
        }
        return nil
    }

    private func cleanSerial(_ serial: String) -> String {
        var s = serial.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("0X") {
            s.removeFirst(2)
        }
        while s.hasPrefix("0") && s.count > 1 {
            s.removeFirst()
        }
        return s
    }

    public func hasPrivateKey(for serialNumber: String, certData: Data? = nil) -> Bool {
        if CertificateManager.shared.getSignableCertificate(for: serialNumber) != nil {
            return true
        }

        let targetSerial = cleanSerial(serialNumber)
        var allSignables = CertificateManager.shared.getAllLocalCertificates()
        if let active = CertificateManager.shared.activeCertificate?.certificate {
            if !allSignables.contains(where: { cleanSerial($0.serialNumber) == cleanSerial(active.serialNumber) }) {
                allSignables.append(active)
            }
        }

        for signable in allSignables {
            if cleanSerial(signable.serialNumber) == targetSerial {
                return true
            }
            if let cData = certData, let sData = signable.data, cData == sData {
                return true
            }
        }
        return false
    }

    public func hasPrivateKey(for cert: ALTX509Certificate) -> Bool {
        return hasPrivateKey(for: cert.serialNumber, certData: cert.data)
    }

    public func isProfileReadyToSign(_ profile: ALTProvisioningProfile) -> Bool {
        return getMatchingCertificate(for: profile) != nil && profile.expirationDate > Date()
    }

    public func getAssignedProfile(for bundleIdentifier: String) -> ALTProvisioningProfile? {
        guard let uuidString = getAssignedProfilesDict()[bundleIdentifier],
              let uuid = UUID(uuidString: uuidString) else {
            return nil
        }
        return getProfile(uuid: uuid)
    }

    public func setAssignedProfile(_ profile: ALTProvisioningProfile?, for bundleIdentifier: String) {
        var assignments = getAssignedProfilesDict()
        if let profile = profile {
            assignments[bundleIdentifier] = profile.uuid.uuidString
            debugLog("[ProfileManager] Assigned profile '\(profile.name)' (\(profile.uuid)) to app '\(bundleIdentifier)'")
        } else {
            assignments.removeValue(forKey: bundleIdentifier)
            debugLog("[ProfileManager] Cleared assigned profile for app '\(bundleIdentifier)'")
        }
        saveAssignedProfilesDict(assignments)
    }

    public func assignProfile(uuid: UUID, for bundleIdentifier: String) {
        var assignments = getAssignedProfilesDict()
        assignments[bundleIdentifier] = uuid.uuidString
        saveAssignedProfilesDict(assignments)
        debugLog("[ProfileManager] Assigned profile UUID '\(uuid)' to app '\(bundleIdentifier)'")
    }

    public func cleanupStaleAssignments() {
        guard DatabaseManager.shared.isStarted else { return }
        let context = DatabaseManager.shared.viewContext
        context.performAndWait {
            let request = InstalledApp.fetchRequest() as NSFetchRequest<InstalledApp>
            guard let apps = try? context.fetch(request) else { return }

            let validIDs = Set(apps.flatMap { [$0.bundleIdentifier, $0.resignedBundleIdentifier] })
            var currentAssignments = getAssignedProfilesDict()
            let originalCount = currentAssignments.count

            currentAssignments = currentAssignments.filter { bundleID, _ in
                validIDs.contains(bundleID)
            }

            if currentAssignments.count != originalCount {
                saveAssignedProfilesDict(currentAssignments)
                debugLog("[ProfileManager] Cleaned up \(originalCount - currentAssignments.count) stale profile assignments")
            }
        }
    }

    public func getAppsUsingProfile(uuid: UUID) -> [String] {
        cleanupStaleAssignments()
        let uuidStr = uuid.uuidString
        return getAssignedProfilesDict().compactMap { key, value in
            value == uuidStr ? key : nil
        }
    }

    private func getAssignedProfilesDict() -> [String: String] {
        return UserDefaults.standard.dictionary(forKey: assignedProfilesKey) as? [String: String] ?? [:]
    }

    private func saveAssignedProfilesDict(_ dict: [String: String]) {
        UserDefaults.standard.set(dict, forKey: assignedProfilesKey)
    }
}
