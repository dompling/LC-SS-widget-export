//
//  AccountVerificationRow.swift
//  SideStore
//
//  Created by Magesh K on 13/09/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
import SideSign

final class AccountVerificationRow: InsetGroupTableViewCell {
    static let reuseIdentifier = "AccountVerificationRow"
    static let preferredHeight: CGFloat = 60.0
    
    enum Status: Equatable {
        case completed
        case checking
        case actionRequired(certMissing: Bool, deviceUnregistered: Bool)
    }
    
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let iconImageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    
    init(reuseIdentifier: String? = AccountVerificationRow.reuseIdentifier) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        self.setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setupViews()
    }
    
    private func setupViews() {
        self.style = .bottom
        self.backgroundColor = .clear
        self.contentView.backgroundColor = .clear
        self.backgroundConfiguration = .clear()
        self.tintColor = UIColor.white.withAlphaComponent(0.6)
        self.layoutMargins = UIEdgeInsets(top: 8, left: 30, bottom: 8, right: 30)
        
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        
        self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.subtitleLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        self.subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        self.subtitleLabel.numberOfLines = 2
        
        self.iconImageView.translatesAutoresizingMaskIntoConstraints = false
        self.iconImageView.contentMode = .scaleAspectFit
        
        self.spinner.translatesAutoresizingMaskIntoConstraints = false
        self.spinner.color = .white
        self.spinner.hidesWhenStopped = true
        
        let textStack = UIStackView(arrangedSubviews: [self.titleLabel, self.subtitleLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        let rightContainer = UIView()
        rightContainer.translatesAutoresizingMaskIntoConstraints = false
        rightContainer.addSubview(self.iconImageView)
        rightContainer.addSubview(self.spinner)
        
        let mainStack = UIStackView(arrangedSubviews: [textStack, rightContainer])
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.axis = .horizontal
        mainStack.spacing = 12
        mainStack.alignment = .center
        mainStack.distribution = .fill
        
        self.contentView.addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 30),
            mainStack.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -30),
            mainStack.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 8),
            mainStack.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -8),
            
            rightContainer.widthAnchor.constraint(equalToConstant: 24),
            rightContainer.heightAnchor.constraint(equalToConstant: 24),
            
            self.iconImageView.centerXAnchor.constraint(equalTo: rightContainer.centerXAnchor),
            self.iconImageView.centerYAnchor.constraint(equalTo: rightContainer.centerYAnchor),
            self.iconImageView.widthAnchor.constraint(equalToConstant: 22),
            self.iconImageView.heightAnchor.constraint(equalToConstant: 22),
            
            self.spinner.centerXAnchor.constraint(equalTo: rightContainer.centerXAnchor),
            self.spinner.centerYAnchor.constraint(equalTo: rightContainer.centerYAnchor)
        ])
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        self.style = .bottom
        self.backgroundColor = .clear
        self.contentView.backgroundColor = .clear
        self.backgroundConfiguration = .clear()
    }
    
    func configure(with status: Status) {
        self.style = .bottom
        self.backgroundColor = .clear
        self.contentView.backgroundColor = .clear
        self.backgroundConfiguration = .clear()
        switch status {
        case .completed:
            self.titleLabel.text = nil
            self.subtitleLabel.text = nil
            self.iconImageView.image = nil
            self.iconImageView.isHidden = true
            self.spinner.stopAnimating()
            self.accessoryType = .none
            self.isSelectable = false
            
        case .checking:
            self.titleLabel.text = NSLocalizedString("Account Verification", comment: "")
            self.titleLabel.textColor = .white
            self.subtitleLabel.text = NSLocalizedString("Verifying account status...", comment: "")
            self.subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.7)
            self.iconImageView.image = nil
            self.iconImageView.isHidden = true
            self.spinner.startAnimating()
            self.accessoryType = .none
            self.isSelectable = false
            
        case .actionRequired(let certMissing, let deviceUnregistered):
            self.titleLabel.text = NSLocalizedString("Action Required", comment: "")
            self.titleLabel.textColor = .systemOrange
            
            let subtitle: String
            if certMissing && deviceUnregistered {
                subtitle = NSLocalizedString("Signing certificate & device registration pending", comment: "")
            } else if certMissing {
                subtitle = NSLocalizedString("Active signing certificate pending", comment: "")
            } else {
                subtitle = NSLocalizedString("Device registration pending", comment: "")
            }
            self.subtitleLabel.text = subtitle
            self.subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.8)
            
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
            self.iconImageView.image = UIImage(systemName: "exclamationmark.triangle.fill", withConfiguration: symbolConfig)?
                .withTintColor(.systemOrange, renderingMode: .alwaysOriginal)
            self.iconImageView.isHidden = false
            self.spinner.stopAnimating()
            self.accessoryType = .none
            self.isSelectable = true
        }
    }
}

extension AccountVerificationRow {
    static func verifyStatus(for team: ALTTeam) async -> Status {
        let hasActiveCert = CertificateManager.shared.activeCertificate != nil || (try? CertificateManager.shared.loadActiveCertificate()) != nil
        let certMissing = !hasActiveCert
        let isDeviceRegistered = UserDefaults.standard.isDeviceRegistered
        
        if isDeviceRegistered {
            if certMissing {
                return .actionRequired(certMissing: true, deviceUnregistered: false)
            } else {
                return .completed
            }
        }
        
        do {
            let devices = try await DeveloperPortalProxy.shared.fetchDevices(for: team, types: .all)
            let udid = try await fetchUDID()
            let isMatch = devices.contains { $0.identifier.caseInsensitiveCompare(udid) == .orderedSame }
            
            if isMatch {
                UserDefaults.standard.isDeviceRegistered = true
                if certMissing {
                    return .actionRequired(certMissing: true, deviceUnregistered: false)
                } else {
                    return .completed
                }
            } else {
                return .actionRequired(certMissing: certMissing, deviceUnregistered: true)
            }
        } catch {
            verboseLog("[AccountVerificationRow] verifyStatus error fetching devices: \(error)")
            return .actionRequired(certMissing: certMissing, deviceUnregistered: true)
        }
    }
    
    static func resolvePendingActions(for status: Status, team: ALTTeam, presentingViewController: UIViewController) async {
        guard case .actionRequired(let certMissing, let deviceUnregistered) = status else { return }
        
        var pendingItems: [String] = []
        if deviceUnregistered {
            pendingItems.append(NSLocalizedString("Register Device", comment: ""))
        }
        if certMissing {
            pendingItems.append(NSLocalizedString("Provision Signing Certificate", comment: ""))
        }
        
        guard !pendingItems.isEmpty else { return }
        
        let count = pendingItems.count
        let title = count == 1
            ? NSLocalizedString("1 Pending Action", comment: "")
            : String(format: NSLocalizedString("%d Pending Actions", comment: ""), count)
        
        let bulletList = pendingItems.map { "• \($0)" }.joined(separator: "\n")
        let message = NSLocalizedString("The following action(s) from sign-in are required to complete account setup:\n\n\(bulletList)", comment: "")
        
        let confirmed = await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            alert.addAction(UIAlertAction(title: NSLocalizedString("Continue", comment: ""), style: .default) { _ in
                continuation.resume(returning: true)
            })
            presentingViewController.present(alert, animated: true)
        }
        
        guard confirmed else { return }
        
        let initialDescription = deviceUnregistered
            ? NSLocalizedString("Registering device…", comment: "")
            : NSLocalizedString("Provisioning signing certificate…", comment: "")
            
        let progressAlert = UIAlertController(
            title: NSLocalizedString("Setting Up Account", comment: ""),
            message: "\(initialDescription)\n\n\n",
            preferredStyle: .alert
        )
        
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        progressAlert.view.addSubview(spinner)
        
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: progressAlert.view.centerXAnchor),
            spinner.bottomAnchor.constraint(equalTo: progressAlert.view.bottomAnchor, constant: -20)
        ])
        
        await withCheckedContinuation { continuation in
            presentingViewController.present(progressAlert, animated: true) {
                continuation.resume()
            }
        }
        
        func executeStep(description: String, operation: () async throws -> Void) async throws {
            progressAlert.message = "\(description)\n\n\n"
            let startTime = Date()
            try await operation()
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed < 0.5 {
                try? await Task.sleep(nanoseconds: UInt64((0.5 - elapsed) * 1_000_000_000))
            }
        }
        
        let handler = SignInFlowHandler(presentingViewController: presentingViewController)
        handler.showsDoItLater = true
        
        do {
            if deviceUnregistered {
                try await executeStep(description: NSLocalizedString("Registering device…", comment: "")) {
                    let deviceFlow = DeviceRegistrationFlow(handler: handler)
                    _ = try await deviceFlow.registerCurrentDevice(for: team)
                }
            }
            
            if certMissing {
                try await executeStep(description: NSLocalizedString("Provisioning signing certificate…", comment: "")) {
                    let certFlow = CertificateProvisioningFlow(handler: handler)
                    _ = try await certFlow.resolveCertificate(for: team)
                }
            }
        } catch {
            verboseLog("[AccountVerificationRow] resolvePendingActions error: \(error)")
        }
        
        await withCheckedContinuation { continuation in
            progressAlert.dismiss(animated: true) {
                continuation.resume()
            }
        }
        
        if UserDefaults.standard.isDeviceRegistered,
           let activeCert = CertificateManager.shared.activeCertificate?.certificate ?? (try? CertificateManager.shared.loadActiveCertificate())?.certificate
        {
            let resignFlow = CodeSignValidationFlow(handler: handler)
            _ = try? await resignFlow.validateAndResignIfNeeded(
                team: team,
                certificate: activeCert
            )
        }
        
        await handler.complete()
    }
}
