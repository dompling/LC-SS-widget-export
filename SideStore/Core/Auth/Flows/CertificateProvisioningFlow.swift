//
//  CertificateProvisioningFlow.swift
//  SideStore
//
//  Created by Magesh K on 13/09/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
import SideSign

protocol CertificateProvisioningHandler: AnyObject, Sendable {
    func resolveRevocation(certificates: [ALTX509Certificate], teamType: ALTTeamType) async throws -> RevokeDecision
    func resolveProvisioningError(_ error: Error) async -> ProvisioningErrorDecision
}

final class CertificateProvisioningFlow: @unchecked Sendable {
    weak var handler: CertificateProvisioningHandler?
    let skipCertificateProvisioning: Bool
    private(set) var portalCertificates: [ALTX509Certificate]?
    
    init(handler: CertificateProvisioningHandler? = nil, skipCertificateProvisioning: Bool = false) {
        self.handler = handler
        self.skipCertificateProvisioning = skipCertificateProvisioning
    }
    
    func resolveCertificate(for team: ALTTeam) async throws -> ALTCertificate? {
        while true {
            do {
                return try await self.performCertificateResolution(for: team)
            } catch {
                if let handler = self.handler {
                    let decision = await handler.resolveProvisioningError(error)
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
    
    private func performCertificateResolution(for team: ALTTeam) async throws -> ALTCertificate? {
        let activeCert = CertificateManager.shared.activeCertificate?.certificate
        let isCustomCert = activeCert?.data.map { data in
            let details = parseCertificate(derData: data)
            return !details.subject.contains(team.identifier) && !details.issuer.contains(team.identifier)
        } ?? false
        
        if isCustomCert {
            debugLog("[CertificateProvisioningFlow] Custom active certificate detected (Subject OU mismatch with Team ID '\(team.identifier)'). Bypassing portal fetch.")
            return activeCert
        } else if self.skipCertificateProvisioning {
            return activeCert
        } else {
            let certificate = try await self.fetchCertificate(for: team)
            try CertificateManager.shared.setActiveCertificate(certificate)
            return certificate
        }
    }
    
    func fetchPortalCertificates(for team: ALTTeam) async throws -> [ALTX509Certificate] {
        if let cached = self.portalCertificates {
            return cached
        }
        let fetched = try await DeveloperPortalProxy.shared.fetchCertificates(team: team)
        self.portalCertificates = fetched
        return fetched
    }
    
    private func fetchCertificate(for team: ALTTeam) async throws -> ALTCertificate {
        let portalCertificates = try await DeveloperPortalProxy.shared.fetchCertificates(team: team)
        self.portalCertificates = portalCertificates
        
        let mainBundleCertSerial = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.certificateID) as? String
        
        if let activeCert = CertificateManager.shared.activeCertificate,
           let certificate = portalCertificates.first(where: { $0.serialNumber == activeCert.serialNumber }) 
        {
            var keyStoreCert = activeCert.certificate
            keyStoreCert.machineIdentifier = certificate.machineIdentifier

            if let mainBundleCertSerial = mainBundleCertSerial, 
                mainBundleCertSerial.lowercased() != activeCert.serialNumber.lowercased() 
            {
                debugLog("[CertificateProvisioningFlow] Active certificate (\(activeCert.serialNumber)) and running bundle certificate (\(mainBundleCertSerial)) mismatch detected. Running Bundle Certificate is still active on the Paid account portal. Using active Keychain certificate.")
            }
            return keyStoreCert
        }
        
        if let mainBundleCertSerial = mainBundleCertSerial,
           let certificate = portalCertificates.first(where: { $0.serialNumber.lowercased() == mainBundleCertSerial.lowercased() }),
           var cert = CertificateManager.shared.getSignableCertificate(for: mainBundleCertSerial, fallbackPassword: certificate.machineIdentifier) 
        {
            cert.machineIdentifier = certificate.machineIdentifier
            debugLog("[CertificateProvisioningFlow] Using running bundle certificate (\(cert.serialNumber)) with valid private key from signable cache.")
            return cert
        }
        
        if portalCertificates.isEmpty {
            return try await self.requestCertificate(for: team)
        } else {
            return try await self.replaceCertificate(portalCertificates: portalCertificates, for: team)
        }
    }
    
    private func requestCertificate(for team: ALTTeam) async throws -> ALTCertificate {
        let deviceName = await UIDevice.current.name
        let accountName = team.account?.firstName ?? team.name
        let machineName = "SideStore - \(accountName)'s \(deviceName)"
        debugLog("[CertificateProvisioningFlow] Requesting certificate for machineName '\(machineName)'...")

        do {
            let newPortalCertificate = try await DeveloperPortalProxy.shared.createCertificate(machineName: machineName, team: team)
            debugLog("[CertificateProvisioningFlow] Successfully requested new portal certificate (Serial: \(newPortalCertificate.serialNumber)).")
            
            let portalCertificates = try await DeveloperPortalProxy.shared.fetchCertificates(team: team)
            self.portalCertificates = portalCertificates

            let finalCert: ALTCertificate
            if let fullX509 = portalCertificates.first(where: { $0.serialNumber.lowercased() == newPortalCertificate.serialNumber.lowercased() }) {
                finalCert = ALTCertificate(x509: fullX509, privateKey: newPortalCertificate.privateKey)
            } else {
                finalCert = newPortalCertificate
            }

            return finalCert
        } catch {
            debugLog("[CertificateProvisioningFlow] requestCertificate: Failed with error: \(error)")
            throw error
        }
    }
    
    private func replaceCertificate(portalCertificates: [ALTX509Certificate], for team: ALTTeam) async throws -> ALTCertificate {
        let iosCertificates = portalCertificates.filter { cert in
            let nameLower = cert.name.lowercased()
            return nameLower.contains("ios development") || nameLower.contains("iphone developer")
        }

        debugLog("[CertificateProvisioningFlow] replaceCertificate: Starting. Total certs on portal: \(portalCertificates.count), iOS Development certs: \(iosCertificates.count)")
        
        if iosCertificates.isEmpty {
            debugLog("[CertificateProvisioningFlow] replaceCertificate: No iOS Development certificates found on portal. Requesting new...")
            return try await self.requestCertificate(for: team)
        }
        
        if let handler = self.handler {
            debugLog("[CertificateProvisioningFlow] replaceCertificate: Presenting revoke alert for \(iosCertificates.count) iOS Development cert(s)...")
            let action = try await handler.resolveRevocation(certificates: iosCertificates, teamType: team.type)
            debugLog("[CertificateProvisioningFlow] replaceCertificate: User action was \(action)")
            switch action {
            case .keepExisting:
                debugLog("[CertificateProvisioningFlow] replaceCertificate: Keeping existing, calling requestCertificate...")
                return try await self.requestCertificate(for: team)
                
            case .revokeSelected(let certsToRevoke):
                debugLog("[CertificateProvisioningFlow] replaceCertificate: Revoking \(certsToRevoke.count) selected certificate(s)...")
                var firstError: Error? = nil

                for certificate in certsToRevoke {
                    do {
                        debugLog("[CertificateProvisioningFlow] replaceCertificate: Revoking certificate '\(certificate.machineName ?? certificate.name)' (Serial: \(certificate.serialNumber))...")
                        _ = try await DeveloperPortalProxy.shared.revokeCertificate(certificate, team: team)
                        debugLog("[CertificateProvisioningFlow] replaceCertificate: Revoke succeeded.")
                    } catch {
                        debugLog("[CertificateProvisioningFlow] replaceCertificate: Revoke failed with error: \(error)")
                        if firstError == nil {
                            firstError = error
                        }
                    }
                }

                if let error = firstError {
                    debugLog("[CertificateProvisioningFlow] replaceCertificate: Error occurred during revocation, throwing...")
                    throw error
                } else {
                    debugLog("[CertificateProvisioningFlow] replaceCertificate: Selected certificates successfully revoked. Requesting new certificate...")
                    return try await self.requestCertificate(for: team)
                }
            }
        } else {
            return try await self.requestCertificate(for: team)
        }
    }
}
