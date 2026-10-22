//
//  SetProfileAlertViewController.swift
//  SideStore
//
//  Created by Magesh K on 14/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
import SideSign

final class SetProfileAlertViewController: UIViewController {
    let installedApp: InstalledApp
    let targetProfile: ALTProvisioningProfile
    let targetCertificate: ALTCertificate?

    init(installedApp: InstalledApp, profile: ALTProvisioningProfile, certificate: ALTCertificate?) {
        self.installedApp = installedApp
        self.targetProfile = profile
        self.targetCertificate = certificate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let currentProfile = ProfileManager.shared.getAssignedProfile(for: installedApp.bundleIdentifier)
        let currentCertName: String
        if let currentProfile = currentProfile,
           let matchingCert = ProfileManager.shared.getMatchingCertificate(for: currentProfile) {
            currentCertName = matchingCert.name
        } else if let signingCert = CertificateManager.shared.getSigningCertificate(for: installedApp) {
            currentCertName = signingCert.name
        } else {
            currentCertName = "Active Developer Cert"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none

        let currentProfileName = currentProfile?.name ?? "Default (Apple ID Managed)"
        let currentProfileBundleID = currentProfile?.bundleIdentifier ?? installedApp.bundleIdentifier
        let currentProfileExpiry = currentProfile != nil ? formatter.string(from: currentProfile!.expirationDate) : formatter.string(from: installedApp.expirationDate)

        let targetProfileName = targetProfile.name
        let targetProfileBundleID = targetProfile.bundleIdentifier
        let targetProfileExpiry = formatter.string(from: targetProfile.expirationDate)
        let targetCertName = targetCertificate?.name ?? "None"
        let targetCertSerial = targetCertificate?.serialNumber ?? "N/A"
        let targetTeam = "\(targetProfile.teamName) (\(targetProfile.teamIdentifier))"

        let details = """
          • App: \(installedApp.name)
          • Bundle ID: \(installedApp.resignedBundleIdentifier)

        [CURRENT PROVISIONING PROFILE]
          • Name: \(currentProfileName)
          • Bundle ID: \(currentProfileBundleID)
          • Expires: \(currentProfileExpiry)
          • Signer: \(currentCertName)

        [TARGET PROVISIONING PROFILE]
          • Name: \(targetProfileName)
          • Bundle ID: \(targetProfileBundleID)
          • Expires: \(targetProfileExpiry)
          • Team: \(targetTeam)
          • Signer: \(targetCertName)
          • Serial: \(targetCertSerial)
        """

        let detailsLabel = UILabel()
        detailsLabel.text = details
        detailsLabel.font = .systemFont(ofSize: 11, weight: .regular)
        detailsLabel.textColor = .secondaryLabel
        detailsLabel.numberOfLines = 0
        detailsLabel.textAlignment = .left
        detailsLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(detailsLabel)

        NSLayoutConstraint.activate([
            detailsLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            detailsLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
            detailsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            detailsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10)
        ])

        self.preferredContentSize = CGSize(width: 290, height: 290)
    }
}
