//
//  SetCertificateAlertViewController.swift
//  SideStore
//
//  Created by Magesh K on 1/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
import SideSign

final class SetCertificateAlertViewController: UIViewController {
    let installedApp: InstalledApp
    let targetCertificate: ALTX509Certificate
    let viewModel: CertificatesViewModel
    
    init(installedApp: InstalledApp, certificate: ALTX509Certificate, viewModel: CertificatesViewModel = CertificatesViewModel()) {
        self.installedApp = installedApp
        self.targetCertificate = certificate
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let appCertSerial = installedApp.certificateSerialNumber
        var currentCertObj = viewModel.getSigningCertificate(for: installedApp)
        
        if currentCertObj == nil, let serial = appCertSerial {
            currentCertObj = viewModel.getLocalX509Certificate(serialNumber: serial)
        }
        
        let currentName = currentCertObj?.name ?? "N/A"
        let currentMachine = currentCertObj?.machineName ?? "N/A"
        let currentSerial = currentCertObj?.serialNumber ?? appCertSerial ?? "None"
        let currentEmail = currentCertObj?.requesterEmail ?? "N/A"
        let currentBrief = getBriefInfo(for: currentCertObj?.data)
        let currentType = currentBrief?.type ?? "N/A"
        let currentValidity = currentBrief != nil ? "\(currentBrief!.validFrom) - \(currentBrief!.validUntil)" : "N/A"
        
        let targetName = targetCertificate.name
        let targetMachine = targetCertificate.machineName ?? "N/A"
        let targetSerial = targetCertificate.serialNumber
        let targetEmail = targetCertificate.requesterEmail ?? "N/A"
        let targetBrief = getBriefInfo(for: targetCertificate.data)
        let targetType = targetBrief?.type ?? "N/A"
        let targetValidity = targetBrief != nil ? "\(targetBrief!.validFrom) - \(targetBrief!.validUntil)" : "N/A"
        
        debugLog("[SetCertAlert] appName: '\(installedApp.name)', appCertSerial: '\(appCertSerial ?? "nil")'")
        debugLog("[SetCertAlert] currentCertObj found: \(currentCertObj != nil), serial: '\(currentSerial)', name: '\(currentName)', machine: '\(currentMachine)', email: '\(currentEmail)'")
        debugLog("[SetCertAlert] targetCert serial: '\(targetSerial)', name: '\(targetName)', machine: '\(targetMachine)', email: '\(targetEmail)'")
        
        let details = """
          • App: \(installedApp.name)
          • Bundle ID: \(installedApp.resignedBundleIdentifier)

        [CURRENT APP CERTIFICATE]
          • Name: \(currentName)
          • Machine: \(currentMachine)
          • Serial: \(currentSerial)
          • Type: \(currentType)
          • Validity: \(currentValidity)
          • Email: \(currentEmail)

        [TARGET CERTIFICATE]
          • Name: \(targetName)
          • Machine: \(targetMachine)
          • Serial: \(targetSerial)
          • Type: \(targetType)
          • Validity: \(targetValidity)
          • Email: \(targetEmail)
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
