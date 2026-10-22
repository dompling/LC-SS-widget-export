//
//  CodeSignValidationFlow.swift
//  SideStore
//
//  Created by Magesh K on 13/09/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
import SideSign

protocol CodeSignValidationHandler: AnyObject, Sendable {
    func resolveResign(mismatchReason: CodeSignValidationReason, context: StandaloneOperationContext) async throws -> Bool
}

final class CodeSignValidationFlow: @unchecked Sendable {
    weak var handler: CodeSignValidationHandler?
    
    init(handler: CodeSignValidationHandler? = nil) {
        self.handler = handler
    }
    
    @discardableResult
    func validateAndResignIfNeeded(
        team: ALTTeam,
        certificate: ALTCertificate,
        portalCertificates: [ALTX509Certificate]? = nil,
        context: StandaloneOperationContext? = nil
    ) async throws -> Bool {
        verboseLog("[CodeSignValidationFlow] validateAndResignIfNeeded: entering method")
        guard let appBundle = ALTApplication(fileURL: Bundle.Info.activeBundleURL), 
              let provisioningProfile = appBundle.provisioningProfile else 
        {
            verboseLog("[CodeSignValidationFlow] Application bundle or provisioning profile nil, returning false")
            return false
        }
        
        let certificates: [ALTX509Certificate]
        if let portalCertificates = portalCertificates {
            certificates = portalCertificates
        } else {
            certificates = try await DeveloperPortalProxy.shared.fetchCertificates(team: team)
        }
        
        let result = CodeSignValidator.validate(
            runningProfile: provisioningProfile,
            portalCertificates: certificates,
            signerCertificate: certificate.x509,
            signerTeam: team
        )
        
        switch result {
        case .success:
            verboseLog("[CodeSignValidationFlow] Validation succeeded, no resign required.")
            return false
            
        case .failure(let reason):
            debugLog("[CodeSignValidationFlow] Signing certificate mismatch detected: \(reason)")
            
            if team.type != .free && (reason == .privateKeyLost || reason == .externalSigner) {
                debugLog("[CodeSignValidationFlow] Running certificate is still active on the Paid account portal. Skipping resign screen.")
                return false
            }
            
            guard let handler = self.handler else {
                debugLog("[CodeSignValidationFlow] No handler available to resolve resign.")
                return false
            }
            
            let operationContext = context ?? StandaloneOperationContext(
                steps: .signIn,
                dbBackgroundContext: DatabaseManager.shared.persistentContainer.newBackgroundContext()
            )
            
            do {
                return try await handler.resolveResign(mismatchReason: reason, context: operationContext)
            } catch {
                verboseLog("[CodeSignValidationFlow] Error occurred when handling resolveResign: \(error)")
                return false
            }
        }
    }
}
