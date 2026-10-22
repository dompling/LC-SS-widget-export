//
//  CodeSignValidator.swift
//  SideStore
//
//  Created by Magesh K on 6/28/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SideSign

public enum CodeSignValidationReason: Error {
    /// The certificate used to sign the current installation has expired.
    case expired
    
    /// The certificate was explicitly revoked on the Apple Developer portal.
    case revoked
    
    /// The certificate was automatically revoked because a free account is limited to 1 active certificate.
    case freeAccountLimitRevoked
    
    /// The active developer team has changed.
    case differentTeam
    
    /// The logged-in Apple ID account has changed.
    case differentAccount
    
    /// The private key for the active certificate is missing from the device's keychain.
    case privateKeyLost
    
    /// SideStore was installed by an external tool (e.g., Xcode or AltStore) using a different certificate.
    case externalSigner
    
    /// The current installation's provisioning profile is missing or invalid.
    case missingProfile
    
    /// Could not extract the leaf signing certificate from the app binary.
    case missingCertificate
}

public struct CodeSignValidator {
    
    public static func validate(
        runningProfile: ALTProvisioningProfile?,
        portalCertificates: [ALTX509Certificate]?,
        signerCertificate: ALTX509Certificate,
        signerTeam: ALTTeam
    ) -> Result<Void, CodeSignValidationReason> {
        
        guard let runningProfile = runningProfile else {
            debugLog("[CodeSignValidator] Validation failed: missingProfile (runningProfile is nil)")
            return .failure(.missingProfile)
        }
        
        let runningCert = CertificateManager.shared.getSigningCertificate(at: Bundle.Info.activeBundleURL)
        guard let runningCert = runningCert else {
            debugLog("[CodeSignValidator] Validation failed: missingCertificate (failed to parse runningCert from binary)")
            return .failure(.missingCertificate)
        }
        
        // 1. Expired Certificate / Profile
        if runningProfile.expirationDate <= Date() {
            debugLog("[CodeSignValidator] Validation failed: expired (running profile is expired: \(runningProfile.expirationDate))")
            return .failure(.expired)
        } else if runningCert.expiryDate <= Date() {
            debugLog("[CodeSignValidator] Validation failed: expired (running certificate is expired: \(runningCert.expiryDate))")
            return .failure(.expired)
        }
        
        // 2. Different Account / Team
        let runningTeamID = runningProfile.teamIdentifier
        if runningTeamID != signerTeam.identifier {
            // Check if the Apple ID email matches.
            if let requesterEmail = runningCert.requesterEmail, !requesterEmail.isEmpty,
                let activeAppleID = signerTeam.account?.appleID,
                requesterEmail.lowercased() != activeAppleID.lowercased() 
            {
                debugLog("[CodeSignValidator] Validation failed: differentAccount (running profile email '\(requesterEmail)' != active account Apple ID '\(activeAppleID)')")
                return .failure(.differentAccount)
            } else {
                debugLog("[CodeSignValidator] Validation failed: differentTeam (running profile team '\(runningTeamID)' != active team '\(signerTeam.identifier)')")
                return .failure(.differentTeam)
            }
        }
        
        // 3. Revoked Certificate (Only checked if portal certificates were fetched)
        if let portalCertificates = portalCertificates {
            let isRunningCertActive = portalCertificates.contains { $0.serialNumber == runningCert.serialNumber }
            if !isRunningCertActive {
                if signerTeam.type == .free {
                    debugLog("[CodeSignValidator] Validation failed: freeAccountLimitRevoked (certificate is no longer active on portal for free account)")
                    return .failure(.freeAccountLimitRevoked)
                } else {
                    debugLog("[CodeSignValidator] Validation failed: revoked (certificate is no longer active on portal)")
                    return .failure(.revoked)
                }
            }
        }
        
        // 4. Mismatch / Private Key Lost / External Signer
        let hasCurrentSignerCert = runningProfile.certificates.contains { $0.serialNumber == signerCertificate.serialNumber }
        if !hasCurrentSignerCert {
            if let machineName = runningCert.machineName, (machineName.starts(with: "SideStore") || machineName.starts(with: "AltStore")) {
                debugLog("[CodeSignValidator] Validation failed: privateKeyLost (running profile cert mismatch, cert created by SideStore/AltStore: \(machineName))")
                return .failure(.privateKeyLost)
            } else {
                debugLog("[CodeSignValidator] Validation failed: externalSigner (running profile cert mismatch, cert not created by SideStore/AltStore: \(runningCert.machineName ?? "N/A"))")
                return .failure(.externalSigner)
            }
        }
        
        debugLog("[CodeSignValidator] Validation succeeded!")
        return .success(())
    }
}
