//
//  SelectProfileViewController.swift
//  SideStore
//
//  Created by Magesh K on 14/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
import SwiftUI
import SideSign

struct ProfileRowItemView: View {
    let profile: ALTProvisioningProfile
    let isCurrent: Bool
    let matchingCert: ALTCertificate?

    private var isExpired: Bool {
        profile.expirationDate < Date()
    }

    private var isReady: Bool {
        matchingCert != nil && !isExpired
    }

    private var expirationString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: profile.expirationDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(profile.bundleIdentifier)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                }
            }

            HStack(spacing: 8) {
                if isExpired {
                    Label("Expired", systemImage: "xmark.octagon.fill")
                        .font(.caption2)
                        .foregroundColor(.red)
                } else if matchingCert != nil {
                    Label("Ready to Sign", systemImage: "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                } else {
                    Label("Missing .p12", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }

                Spacer()

                Text("Expires: \(expirationString)")
                    .font(.caption2)
                    .foregroundColor(isExpired ? .red : .secondary)
            }

            if let cert = matchingCert {
                HStack(spacing: 4) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text("Cert: \(cert.name)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

final class SelectProfileViewController: UITableViewController {
    let installedApp: InstalledApp
    var onSelectProfile: ((ALTProvisioningProfile) -> Void)?

    private var profiles: [ALTProvisioningProfile] = []

    init(installedApp: InstalledApp) {
        self.installedApp = installedApp
        #if !os(tvOS)
        super.init(style: .insetGrouped)
        #else
        super.init(style: .grouped)
        #endif
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = NSLocalizedString("Select Provisioning Profile", comment: "")
        self.profiles = ProfileManager.shared.getAllLocalProfiles().filter {
            Self.isProfileCompatible($0, for: self.installedApp)
        }

        self.view.backgroundColor = .settingsBackground
        self.tableView.backgroundColor = .settingsBackground

        #if !os(tvOS)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .settingsBackground
        appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        self.navigationItem.standardAppearance = appearance
        self.navigationItem.scrollEdgeAppearance = appearance
        #endif

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))

        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ProfileCell")
    }

    static func isProfileCompatible(_ profile: ALTProvisioningProfile, for installedApp: InstalledApp) -> Bool {
        guard profile.expirationDate > Date() else { return false }
        let profileID = profile.bundleIdentifier
        let appID = installedApp.bundleIdentifier
        let resignedID = installedApp.resignedBundleIdentifier

        let isWildcard = profileID == "*" || profileID.hasSuffix(".*") || profileID.hasSuffix("*")
        let isExactMatch = (profileID.lowercased() == appID.lowercased()) || (profileID.lowercased() == resignedID.lowercased())
        guard isWildcard || isExactMatch else { return false }

        return ProfileManager.shared.getMatchingCertificate(for: profile) != nil
    }

    @objc private func cancelTapped() {
        self.dismiss(animated: true)
    }

    func present(from presentingViewController: UIViewController) {
        let compatibleProfiles = ProfileManager.shared.getAllLocalProfiles().filter {
            Self.isProfileCompatible($0, for: self.installedApp)
        }

        guard !compatibleProfiles.isEmpty else {
            let alert = UIAlertController(
                title: NSLocalizedString("No Compatible Profiles", comment: ""),
                message: String(format: NSLocalizedString("No unexpired provisioning profiles matching '%@' with an imported signing certificate (.p12) were found locally.\n\nPlease go to Settings -> Profiles Management to import and configure a profile with its matching certificate.", comment: ""), self.installedApp.bundleIdentifier),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
            presentingViewController.present(alert, animated: true)
            return
        }

        let nav = UINavigationController(rootViewController: self)
        #if !os(tvOS)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        #else
        nav.modalPresentationStyle = .fullScreen
        #endif
        presentingViewController.present(nav, animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return profiles.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ProfileCell", for: indexPath)
        let profile = profiles[indexPath.row]
        let currentAssigned = ProfileManager.shared.getAssignedProfile(for: installedApp.bundleIdentifier)
        let isCurrent = (currentAssigned?.uuid == profile.uuid)
        let matchingCert = ProfileManager.shared.getMatchingCertificate(for: profile)

        if #available(iOS 16.0, tvOS 16.0, *) {
            cell.contentConfiguration = UIHostingConfiguration {
                ProfileRowItemView(profile: profile, isCurrent: isCurrent, matchingCert: matchingCert)
            }
        } else {
            cell.textLabel?.numberOfLines = 0
            cell.textLabel?.text = "\(profile.name)\(isCurrent ? " (Current)" : "")\nBundle ID: \(profile.bundleIdentifier)\nExpires: \(profile.expirationDate)"
            cell.accessoryType = isCurrent ? .checkmark : .none
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let profile = profiles[indexPath.row]
        let matchingCert = ProfileManager.shared.getMatchingCertificate(for: profile)

        let contentVC = SetProfileAlertViewController(installedApp: self.installedApp, profile: profile, certificate: matchingCert)
        let confirmAlert = UIAlertController(
            title: NSLocalizedString("Set Profile Confirmation", comment: ""),
            message: NSLocalizedString("Confirm applying this provisioning profile:", comment: ""),
            preferredStyle: .alert
        )
        confirmAlert.setValue(contentVC, forKey: "contentViewController")

        let setAction = UIAlertAction(title: NSLocalizedString("Set & Resign", comment: ""), style: .default) { [weak self] _ in
            self?.dismiss(animated: true) {
                self?.onSelectProfile?(profile)
            }
        }
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel)

        confirmAlert.addAction(cancelAction)
        confirmAlert.addAction(setAction)

        self.present(confirmAlert, animated: true)
    }
}
