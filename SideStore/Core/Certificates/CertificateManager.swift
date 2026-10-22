//
//  CertificateManager.swift
//  SideStore
//
//  Created by Magesh K on 1/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SideSign
import CodeSignKit

public struct ActiveSigningCertificate: Sendable {
    public let certificate: ALTCertificate
    public let p12Data: Data
    public let password: String?
    
    public var serialNumber: String {
        certificate.serialNumber
    }

    fileprivate init(certificate: ALTCertificate, p12Data: Data, password: String?) {
        self.certificate = certificate
        self.p12Data = p12Data
        self.password = password
    }
}

public final class CertificateManager: @unchecked Sendable {
    public static let shared = CertificateManager()
    
    private let serialsKey = "importedCertificateSerials"
    private let metadataPrefix = "certMetadata_"
    
    public private(set) var activeCertificate: ActiveSigningCertificate?
    
    private init() {
        _ = try? loadActiveCertificate()
    }
    
    public static func parse(_ data: Data, password: String?) throws -> ALTCertificate {
        if let password = password {
            return try ALTCertificate(p12Data: data, password: password)
        } else {
            return try ALTCertificate(p12Data: data)
        }
    }

    public static func convert(_ cert: ALTCertificate, password: String?) throws -> Data {
        if let password = password {
            return try cert.encryptedP12Data(password: password)
        } else {
            return try cert.unencryptedP12Data()
        }
    }

    // MARK: - Active Keychain Certificate Encapsulation
    
    /// Loads active signing certificate from Keychain into memory.
    @discardableResult
    public func loadActiveCertificate() throws -> ActiveSigningCertificate? {
        guard let data = Keychain.shared.signingCertificate else {
            debugLog("[CertificateManager] loadActiveCertificate: No signingCertificate data found in Keychain.")
            self.activeCertificate = nil
            return nil
        }
        let password = Keychain.shared.signingCertificatePassword
        do {
            let cert = try Self.parse(data, password: password)
            let active = ActiveSigningCertificate(certificate: cert, p12Data: data, password: password)
            self.activeCertificate = active
            debugLog("[CertificateManager] loadActiveCertificate: Successfully loaded certificate (serial: \(cert.serialNumber)).")
            return active
        } catch {
            debugLog("[CertificateManager] loadActiveCertificate failed to load/decrypt certificate: \(error)")
            self.activeCertificate = nil
            throw error
        }
    }

    public func getPassword(for cert: ALTCertificate) -> String? {
        return cert.serialNumber
    }

    public func getPassword(for serialNumber: String) -> String? {
        return serialNumber
    }

    /// Sets active signing certificate in memory cache, encrypts and persists to Keychain.
    public func setActiveCertificate(_ cert: ALTCertificate?) throws {
        if let cert = cert {
            do {
                let password = getPassword(for: cert)
                let p12Data = try Self.convert(cert, password: password)
                Keychain.shared.signingCertificate = p12Data
                Keychain.shared.signingCertificatePassword = password
                saveCertificate(cert)
                let active = ActiveSigningCertificate(certificate: cert, p12Data: p12Data, password: password)
                self.activeCertificate = active
                debugLog("[CertificateManager] setActiveCertificate: Successfully stored certificate (serial: \(cert.serialNumber)).")
            } catch {
                debugLog("[CertificateManager] setActiveCertificate failed to export/encrypt certificate: \(error)")
                throw error
            }
        } else {
            self.activeCertificate = nil
            Keychain.shared.clearCertificates()
            debugLog("[CertificateManager] setActiveCertificate: Cleared active certificate in Keychain.")
        }
    }

    /// Clears active certificate in memory cache and Keychain.
    public func clearActiveCertificate() {
        debugLog("[CertificateManager] clearActiveCertificate: Clearing active certificate.")
        self.activeCertificate = nil
        Keychain.shared.clearCertificates()
    }
    
    // MARK: - Certificate Encoding Helpers
    
    public var activeSigningCertificateBase64Encoded: String? {
        guard let data = activeCertificate?.p12Data else { return nil }
        let base64 = data.base64EncodedString()
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ";/?:@&=+$, ")
        return base64.addingPercentEncoding(withAllowedCharacters: allowed)
    }

    public func saveCertificate(_ cert: ALTCertificate) {
        debugLog("[CertificateManager] saveCertificate started for serial: \(cert.serialNumber)")
        defer { debugLog("[CertificateManager] saveCertificate completed for serial: \(cert.serialNumber)") }
        
        do {
            let password = getPassword(for: cert)
            let p12Data = try Self.convert(cert, password: password)
            debugLog("[CertificateManager] p12Data generated, size: \(p12Data.count)")
            Keychain.shared[certificateSerial: cert.serialNumber] = p12Data
            debugLog("[CertificateManager] Successfully saved p12 to keychain")
        } catch {
            debugLog("[CertificateManager] Failed to export/save p12 to keychain: \(error)")
        }
        
        let serials = getImportedCertificateSerials()
        if !serials.contains(cert.serialNumber) {
            var updatedSerials = serials
            updatedSerials.append(cert.serialNumber)
            setImportedCertificateSerials(updatedSerials)
        }
        
        var metadataDict: [String: String] = getCertificateMetadata(for: cert.serialNumber) ?? [:]
        metadataDict["name"] = cert.name
        metadataDict["serialNumber"] = cert.serialNumber
        if let v = cert.machineIdentifier { metadataDict["machineIdentifier"] = v }
        if let v = cert.machineName { metadataDict["machineName"] = v }
        if let v = cert.requesterEmail { metadataDict["requesterEmail"] = v }
        setCertificateMetadata(metadataDict, for: cert.serialNumber)
    }

    public func saveX509Certificate(_ x509: ALTX509Certificate) {
        debugLog("[CertificateManager] saveX509Certificate started for serial: \(x509.serialNumber)")
        defer { debugLog("[CertificateManager] saveX509Certificate completed for serial: \(x509.serialNumber)") }
        
        if let derData = x509.data {
            debugLog("[CertificateManager] derData exists, size: \(derData.count)")
            Keychain.shared[certificateSerial: x509.serialNumber] = derData
            debugLog("[CertificateManager] Successfully saved der to keychain")
        }
        
        let serials = getImportedCertificateSerials()
        if !serials.contains(x509.serialNumber) {
            var updatedSerials = serials
            updatedSerials.append(x509.serialNumber)
            setImportedCertificateSerials(updatedSerials)
        }
        
        var metadataDict: [String: String] = getCertificateMetadata(for: x509.serialNumber) ?? [:]
        metadataDict["name"] = x509.name
        metadataDict["serialNumber"] = x509.serialNumber
        if let v = x509.machineIdentifier { metadataDict["machineIdentifier"] = v }
        if let v = x509.machineName { metadataDict["machineName"] = v }
        if let v = x509.requesterEmail { metadataDict["requesterEmail"] = v }
        setCertificateMetadata(metadataDict, for: x509.serialNumber)
    }
    
    public func getLocalCertificate(serialNumber: String) -> ALTCertificate? {
        if let active = self.activeCertificate, active.serialNumber == serialNumber {
            return active.certificate
        }
        if let data = Keychain.shared[certificateSerial: serialNumber] {
            if data.isPKCS12 {
                let savedPassword = getPassword(for: serialNumber)
                if var cert = try? Self.parse(data, password: savedPassword) {
                    if let metadata = getCertificateMetadata(for: serialNumber) {
                        cert.machineIdentifier = metadata["machineIdentifier"]
                        cert.machineName = metadata["machineName"]
                        cert.requesterEmail = metadata["requesterEmail"]
                    }
                    return cert
                }
            }
        }
        return nil
    }

    public func getLocalX509Certificate(serialNumber: String) -> ALTX509Certificate? {
        if let cert = getLocalCertificate(serialNumber: serialNumber) {
            return cert.x509
        }
        if let data = Keychain.shared[certificateSerial: serialNumber] {
            let x509: ALTX509Certificate? = data.isPKCS12
                ? (try? Self.parse(data, password: getPassword(for: serialNumber)))?.x509
                : ALTX509Certificate(data: data)
            if var x509 {
                if let metadata = getCertificateMetadata(for: serialNumber) {
                    x509.machineIdentifier = metadata["machineIdentifier"]
                    x509.machineName = metadata["machineName"]
                    x509.requesterEmail = metadata["requesterEmail"]
                }
                return x509
            }
        }
        return nil
    }
    
    public func getAllLocalCertificates() -> [ALTCertificate] {
        let serials = getImportedCertificateSerials()
        debugLog("[CertificateManager] getAllLocalCertificates count: \(serials.count)")
        var certs: [ALTCertificate] = []
        for serial in serials {
            if let cert = getLocalCertificate(serialNumber: serial) {
                certs.append(cert)
            }
        }
        return certs
    }

    public func getAllLocalX509Certificates() -> [ALTX509Certificate] {
        let serials = getImportedCertificateSerials()
        var certs: [ALTX509Certificate] = []
        for serial in serials {
            if let x509 = getLocalX509Certificate(serialNumber: serial) {
                certs.append(x509)
            }
        }
        return certs
    }
    
    public func deleteCertificate(serialNumber: String) {
        debugLog("[CertificateManager] deleteCertificate: \(serialNumber)")
        if self.activeCertificate?.serialNumber == serialNumber {
            clearActiveCertificate()
        }
        Keychain.shared[certificateSerial: serialNumber] = nil
        setCertificateMetadata(nil, for: serialNumber)
        var serials = getImportedCertificateSerials()
        serials.removeAll { $0 == serialNumber }
        setImportedCertificateSerials(serials)
    }

    public func getSignableCertificate(for serialNumber: String = "", fallbackPassword: String? = nil) -> ALTCertificate? {
        if let cert = getLocalCertificate(serialNumber: serialNumber) {
            return cert
        }
        
        if let cert = loadEmbeddedCertificate(for: serialNumber, fallbackPassword: fallbackPassword) {
            return cert
        }
        
        debugLog("[CertificateManager] getSignableCertificate: No signable certificate found for serial \(serialNumber).")
        return nil
    }

    private func loadEmbeddedCertificate(for serialNumber: String, fallbackPassword: String?) -> ALTCertificate? {
        let targetBundle = Bundle.main
        if FileManager.default.fileExists(atPath: targetBundle.certificateURL.path),
           let data = try? Data(contentsOf: targetBundle.certificateURL)
        {
            let possiblePasswords: [(name: String, value: String?)] = [
                ("incomingCertSerial", serialNumber),
                ("fallbackPassword", fallbackPassword),
                ("activeCertSerial", activeCertificate?.certificate.serialNumber),
                ("machineIdentifier", activeCertificate?.certificate.machineIdentifier),
                ("activeCertPassword", activeCertificate?.password),
                ("keychainPassword", Keychain.shared.signingCertificatePassword),
                ("nil", nil)
            ]

            var signableCert: ALTCertificate?
            for (pwdName, password) in possiblePasswords {
                verboseLog("[CertificateManager] getSignableCertificate: Attempting decryption with password source '\(pwdName)'...")
                if let cert = try? ALTCertificate(p12Data: data, password: password) {
                    signableCert = cert
                    if cert.serialNumber.lowercased() == serialNumber.lowercased() {
                        debugLog("[CertificateManager] getSignableCertificate: Decrypted embedded p12 using '\(pwdName)' with matching serial '\(cert.serialNumber)'.")
                        break
                    } else {
                        verboseLog("[CertificateManager] getSignableCertificate: Decrypted embedded p12 using '\(pwdName)', but serial mismatch (certSerial: \(cert.serialNumber), targetSerial: \(serialNumber)).")
                    }
                } else {
                    verboseLog("[CertificateManager] getSignableCertificate: Failed to decrypt embedded p12 using password source '\(pwdName)'.")
                }
            }

            if signableCert != nil || serialNumber.isEmpty {
                debugLog("[CertificateManager] getSignableCertificate: Returning certificate (serial: '\(signableCert?.serialNumber ?? "nil")', targetSerial: '\(serialNumber)').")
                return signableCert
            }
        }
        return nil
    }

    // Reads the Mach-O binary contents of an app bundle to extract its leaf signing certificate.
    private func readBinaryCertificate(at url: URL) -> ALTX509Certificate? {
        let executableURL: URL
        if url.pathExtension == "app" {
            guard let execURL = ALTApplication(fileURL: url)?.executableURL else {
                debugLog("[CertificateManager] readBinaryCertificate: Failed to locate executable in bundle: \(url.path)")
                return nil
            }
            executableURL = execURL
        } else {
            executableURL = url
        }
        
        guard let parser = try? MachOParser(url: executableURL) else {
            debugLog("[CertificateManager] readBinaryCertificate: Failed to parse Mach-O at \(executableURL.path)")
            return nil
        }
        
        let certChain = parser.x509Certificates()

        debugLog("[CertificateManager] readBinaryCertificate: Found \(certChain.count) certificate(s) in Mach-O chain.")
        
        for (index, x509Cert) in certChain.enumerated() {
            guard let derData = x509Cert.data else { continue }
            let details = parseCertificate(derData: derData)
            
            // Filter out Root & Intermediate CA certificates
            let subjectDN = details.subject
            let isFilteredOut = subjectDN.contains("Root") || subjectDN.contains("Authority") || subjectDN.contains("Relations")
            
            verboseLog("""
            [CertificateManager] readBinaryCertificate: Certificate [\(index)]:
              - Subject: '\(details.subject)'
              - Issuer: '\(details.issuer)'
              - Serial Hex: '\(details.serialHex)'
              - Valid From: \(details.validFrom?.description ?? "N/A")
              - Valid Until: \(details.validUntil?.description ?? "N/A")
              - Filtered Out: \(isFilteredOut)
              - Parsed ALTX509Certificate: Success (serial: \(x509Cert.serialNumber))
            """)
            
            if isFilteredOut {
                continue
            }
            
            debugLog("[CertificateManager] readBinaryCertificate: Extracted leaf signing certificate from Mach-O (\(executableURL.lastPathComponent))")
            return x509Cert
        }
        return nil
    }

    public func getSigningCertificate(at url: URL) -> ALTX509Certificate? {
        verboseLog("[CertificateManager] Step 1 (Mach-O): Checking \(url.path)...")
        if let binaryX509 = readBinaryCertificate(at: url) {
            debugLog("[CertificateManager] getSigningCertificate: Loaded signing certificate from Mach-O \(url.path) (serial: \(binaryX509.serialNumber)).")
            return binaryX509
        } else {
            verboseLog("[CertificateManager] Step 1 (Mach-O): No valid leaf certificate extracted from Mach-O at \(url.path).")
            return nil
        }
    }

    public func getSigningCertificate(for app: InstalledAppProtocol) -> ALTX509Certificate? {
        let bundleID = app.bundleIdentifier
        let isSelf = app.resignedBundleIdentifier.isAltStoreAppID || app.bundleIdentifier.isAltStoreAppID

        verboseLog("[CertificateManager] getSigningCertificate started for app: \(app.name), isSelf: \(isSelf), bundleID: \(bundleID)")

        // STEP 1: Mach-O Binary Check (Only for SideStore itself)
        if isSelf {
            return self.getSigningCertificate(at: Bundle.Info.activeBundleURL)
        }

        // STEP 2: App Group Cached Certificate Check (For third-party apps)
        let certURL = app.signingCertificateURL
        verboseLog("[CertificateManager] Step 2 (App Group Cached Cert): Checking \(certURL.path)...")

        if FileManager.default.fileExists(atPath: certURL.path) {
            if let derData = try? Data(contentsOf: certURL), let cert = ALTX509Certificate(data: derData) {
                debugLog("[CertificateManager] getSigningCertificate: Loaded cached signing certificate from App Group \(certURL.path) (serial: \(cert.serialNumber))")
                return cert
            } else {
                verboseLog("[CertificateManager] Step 2 (App Group Cached Cert): File exists at \(certURL.path) but failed to parse.")
            }
        }
        verboseLog("[CertificateManager] Step 2 (App Group Cached Cert): No cached certificate found in App Group at \(certURL.path).")

        return nil
    }

    public func isCertificateLocallyCached(serialNumber: String) -> Bool {
        if let activeCert = self.activeCertificate, activeCert.serialNumber == serialNumber {
            return true
        }
        return getImportedCertificateSerials().contains(serialNumber)
    }
}

// MARK: - Private Domain Persistence Boundary Extension

private extension CertificateManager {
    func getImportedCertificateSerials() -> [String] {
        return UserDefaults.standard.stringArray(forKey: serialsKey) ?? []
    }
    
    func setImportedCertificateSerials(_ serials: [String]) {
        UserDefaults.standard.set(serials, forKey: serialsKey)
    }
    
    func getCertificateMetadata(for serial: String) -> [String: String]? {
        return UserDefaults.standard.dictionary(forKey: metadataPrefix + serial) as? [String: String]
    }
    
    func setCertificateMetadata(_ metadata: [String: String]?, for serial: String) {
        if let metadata = metadata {
            UserDefaults.standard.set(metadata, forKey: metadataPrefix + serial)
        } else {
            UserDefaults.standard.removeObject(forKey: metadataPrefix + serial)
        }
    }
}
