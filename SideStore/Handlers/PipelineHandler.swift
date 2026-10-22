//
//  PipelineHandler.swift
//  SideStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit
import SideSign

final class PipelineHandler: PipelineExecutionHandler, 
                             PreflightChecksHandler, 
                             EntitlementsReviewHandler, 
                             ExtensionRemovalHandler, 
                             UnsupportedVersionHandler, 
                             InstallAppHandler, 
                             UserCustomizationHandler,
                             Sendable
{
    var preflightChecksHandler: PreflightChecksHandler { self }
    var entitlementsReviewHandler: EntitlementsReviewHandler { self }
    var extensionRemovalHandler: ExtensionRemovalHandler { self }
    var unsupportedVersionHandler: UnsupportedVersionHandler { self }
    var installAppHandler: InstallAppHandler { self }
    var userCustomizationHandler: UserCustomizationHandler { self }
    
    let isResignActive: Bool
    private let presenterProvider: PresenterProvider?
    
    init(
        isResignActive: Bool = false,
        presenterProvider: PresenterProvider? = nil
    ) {
        self.isResignActive = isResignActive
        self.presenterProvider = presenterProvider
    }

    @MainActor
    private var isPresenterAvailable: Bool {
        return self.activePresenter != nil
    }

    @MainActor
    private var activePresenter: UIViewController? {
        return self.presenterProvider?()
    }
    
    @MainActor
    func resolveBundleIDMismatch(targetID: String, activeEffectiveID: String) async -> Bool {
        guard let presenter = self.activePresenter else {
            return false
        }
        
        let title = NSLocalizedString("Bundle ID Mismatch", comment: "")
        let message = String(format: NSLocalizedString("The app you are installing has a bundle ID (%@) that does not match the active app (%@). Would you like to proceed?", comment: ""), targetID, activeEffectiveID)
        
        return await withCheckedContinuation { continuation in
            let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: UIAlertAction.cancel.title, style: UIAlertAction.cancel.style) { _ in
                continuation.resume(returning: false)
            })
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Proceed", comment: ""), style: .default) { _ in
                continuation.resume(returning: true)
            })
            presenter.present(alertController, animated: true)
        }
    }
    
    @MainActor
    func reviewPermissions(_ permissions: [ALTEntitlement], for app: AppProtocol, mode: PermissionReviewMode) async throws {
        guard let presenter = self.activePresenter else {
            throw OperationError.invalidParameters("PipelineHandler: Cannot review permissions because presenting view controller is unavailable")
        }
        let reviewPermissionsViewController = ReviewPermissionsViewController(app: app, permissions: permissions, mode: mode)
        let navigationController = UINavigationController(rootViewController: reviewPermissionsViewController)
        
        defer {
            navigationController.dismiss(animated: true)
        }
        
        try await withCheckedThrowingContinuation { continuation in
            reviewPermissionsViewController.completionHandler = { result in
                continuation.resume(with: result)
            }
            
            presenter.present(navigationController, animated: true)
        }
    }
    
    @MainActor
    func selectAppExtensionsToRemove(
        appBundle: ALTApplication,
        localAppExtensions: [ALTApplication],
        excessExtensions: Set<ALTApplication>
    ) async throws -> ExtensionRemovalDecision {
        guard let presenter = self.activePresenter else {
            return .removeSelected(excessExtensions)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let firstSentence: String
            if UserDefaults.standard.activeAppLimitIncludesExtensions {
                firstSentence = NSLocalizedString("Non-developer Apple IDs are limited to 3 active apps and app extensions.", comment: "")
            } else {
                firstSentence = NSLocalizedString("Non-developer Apple IDs are limited to creating 10 App IDs per week.", comment: "")
            }
            
            let message = firstSentence + " " + NSLocalizedString("Would you like to remove this app's extensions so they don't count towards your limit? There are \(appBundle.appExtensions.count) Extensions", comment: "")
            
            let alertController = UIAlertController(title: NSLocalizedString("App Contains Extensions", comment: ""), message: message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: UIAlertAction.cancel.title, style: UIAlertAction.cancel.style, handler: { _ in
                continuation.resume(throwing: OperationError.cancelled)
            }))
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Keep App Extensions (Use Main Profile)", comment: ""), style: .default) { _ in
                continuation.resume(returning: .keepAll(useMainProfile: true))
            })
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Keep App Extensions (Register App ID for Each Extension)", comment: ""), style: .default) { _ in
                continuation.resume(returning: .keepAll(useMainProfile: false))
            })
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Remove App Extensions", comment: ""), style: .destructive) { _ in
                continuation.resume(returning: .removeAll)
            })
            
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Choose App Extensions", comment: ""), style: .default) { _ in
                let popoverContentController = AppExtensionViewHostingController(extensions: appBundle.appExtensions) { selection in
                    continuation.resume(returning: .removeSelected(Set(selection)))
                }
                
                let suiview = popoverContentController.view!
                suiview.translatesAutoresizingMaskIntoConstraints = false
                #if !os(tvOS)
                popoverContentController.modalPresentationStyle = .popover
                
                if let popoverPresentationController = popoverContentController.popoverPresentationController {
                    popoverPresentationController.sourceView = presenter.view
                    popoverPresentationController.sourceRect = CGRect(x: 50, y: 50, width: 4, height: 4)
                    popoverPresentationController.delegate = popoverContentController
                    presenter.present(popoverContentController, animated: true)
                } else {
                    continuation.resume(throwing: OperationError.invalidParameters("RemoveAppExtensionsOperation: popoverContentController.popoverPresentationController is nil"))
                }
                #else
                popoverContentController.modalPresentationStyle = .blurOverFullScreen
                presenter.present(popoverContentController, animated: true)
                #endif
            })
            
            presenter.present(alertController, animated: true) {
                if presenter.presentedViewController == nil && !alertController.isViewLoaded {
                    let errMsg = "RemoveAppExtensionsOperation: unable to present dialog, view context not available." +
                                 "\nDid you move to different screen or background after starting the operation?"
                    continuation.resume(throwing: OperationError.invalidParameters(errMsg))
                }
            }
        }
    }
    
    @MainActor
    func resolveUnsupportediOSVersion(errorDescription: String, appName: String, compatibleVersion: String) async throws -> Bool {
        guard let presenter = self.activePresenter else {
            return false
        }
        
        let title = NSLocalizedString("Unsupported iOS Version", comment: "")
        let message = errorDescription + "\n\n" + NSLocalizedString("Would you like to download the last version compatible with this device instead?", comment: "")
        
        return await withCheckedContinuation { continuation in
            let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: UIAlertAction.cancel.title, style: UIAlertAction.cancel.style) { _ in
                continuation.resume(returning: false)
            })
            alertController.addAction(UIAlertAction(title: String(format: NSLocalizedString("Download %@ %@", comment: ""), appName, compatibleVersion), style: .default) { _ in
                continuation.resume(returning: true)
            })
            presenter.present(alertController, animated: true)
        }
    }
    
    func requestBackgroundSuspension() async {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                let alert = UIAlertController(
                    title: "Finish Refresh",
                    message: """
                    To finish refreshing, SideStore must be moved to the background. To do this, you can either go to the Home Screen manually or by hitting Continue. Please reopen SideStore after doing this.
                    """,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: NSLocalizedString("Continue", comment: ""), style: .default, handler: { _ in
                    continuation.resume()
                }))
                
                let presenter = self.activePresenter
                                ?? UIApplication.shared.connectedScenes
                                    .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                                    .first?.rootViewController
                                    
                if var topVC = presenter {
                    while let presented = topVC.presentedViewController {
                        topVC = presented
                    }
                    topVC.present(alert, animated: true)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    func suspendToHomeScreen() async {
        await CellularRefreshManager.shared.turnOnDataIfNeeded()
        await MainActor.run {
            _ = UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
        }
    }
    
    func isAppInForeground() async -> Bool {
        await MainActor.run {
            UIApplication.shared.applicationState == .active
        }
    }
    
    @MainActor
    func resolveInfoPlistCustomization(
        targets: [InfoPlistTarget],
        initialBundleID: String,
        appendTeamID: Bool,
        installedAppIdentities: [String: String],
        teamID: String
    ) async throws -> (modifiedPlists: [String: [String: any Sendable]], appendTeamID: Bool)? {
        debugLog("[PipelineHandler] resolveInfoPlistCustomization (targets: \(targets.count)): initialBundleID='\(initialBundleID)', teamID='\(teamID)', appendTeamID=\(appendTeamID)")
        guard let presenter = self.activePresenter else {
            debugLog("[PipelineHandler] resolveInfoPlistCustomization: activePresenter is nil!")
            var fallback: [String: [String: any Sendable]] = [:]
            for t in targets {
                fallback[t.id] = t.initialPlist
            }
            return (fallback, appendTeamID)
        }

        let result: (modifiedPlists: [String: [String: any Sendable]], appendTeamID: Bool)?
        if UserDefaults.standard.preferSheetForInfoPlistCustomization {
            result = await InfoPlistCustomizationSheetView.present(
                from: presenter,
                targets: targets,
                initialBundleID: initialBundleID,
                appendTeamID: appendTeamID,
                installedAppIdentities: installedAppIdentities,
                teamID: teamID
            )
        } else {
            result = await InfoPlistCustomizationView.present(
                from: presenter,
                targets: targets,
                initialBundleID: initialBundleID,
                appendTeamID: appendTeamID,
                installedAppIdentities: installedAppIdentities,
                teamID: teamID
            )
        }
        debugLog("[PipelineHandler] resolveInfoPlistCustomization result: \(result?.modifiedPlists.count ?? 0) target(s) returned, appendTeamID=\(result?.appendTeamID ?? false)")
        return result
    }

    @MainActor
    func resolveInfoPlistCustomization(
        initialPlist: [String: any Sendable],
        initialBundleID: String,
        appendTeamID: Bool,
        installedAppIdentities: [String: String],
        teamID: String
    ) async throws -> (modifiedPlist: [String: any Sendable], appendTeamID: Bool)? {
        let target = InfoPlistTarget(
            id: initialBundleID,
            name: (initialPlist["CFBundleDisplayName"] as? String) ?? (initialPlist["CFBundleName"] as? String) ?? initialBundleID,
            isExtension: false,
            initialPlist: initialPlist
        )
        guard let result = try await resolveInfoPlistCustomization(
            targets: [target],
            initialBundleID: initialBundleID,
            appendTeamID: appendTeamID,
            installedAppIdentities: installedAppIdentities,
            teamID: teamID
        ) else { return nil }
        let plist = result.modifiedPlists[initialBundleID] ?? initialPlist
        return (plist, result.appendTeamID)
    }


    @MainActor
    func resolveEntitlementsCustomization(
        targets: [EntitlementsTarget],
        teamType: ALTTeamType
    ) async throws -> [String: [String: any Sendable]]? {
        debugLog("[PipelineHandler] resolveEntitlementsCustomization: targets=\(targets.count), teamType=\(teamType.displayName)")
        guard let presenter = self.activePresenter else {
            debugLog("[PipelineHandler] resolveEntitlementsCustomization: activePresenter is nil!")
            var fallback: [String: [String: any Sendable]] = [:]
            for t in targets {
                fallback[t.id] = t.initialEntitlements
            }
            return fallback
        }

        let result: [String: [String: any Sendable]]?
        if UserDefaults.standard.preferSheetForEntitlementsCustomization {
            result = await EntitlementsCustomizationSheetView.present(
                from: presenter,
                targets: targets,
                teamType: teamType
            )
        } else {
            result = await EntitlementsCustomizationView.present(
                from: presenter,
                targets: targets,
                teamType: teamType
            )
        }
        debugLog("[PipelineHandler] resolveEntitlementsCustomization result: \(result?.count) target(s) returned")
        return result
    }

    @MainActor
    func resolveEntitlementsCustomization(
        initialEntitlements: [String: any Sendable],
        bundleID: String,
        teamType: ALTTeamType
    ) async throws -> [String: any Sendable]? {
        let target = EntitlementsTarget(
            id: bundleID,
            name: bundleID,
            isExtension: false,
            initialEntitlements: initialEntitlements
        )
        let result = try await resolveEntitlementsCustomization(targets: [target], teamType: teamType)
        return result?[bundleID]
    }

    @MainActor
    func resolveBundleIDOverride(initialBundleID: String) async throws -> (customID: String, appendTeamID: Bool)? {
        guard let presenter = self.activePresenter else {
            return (initialBundleID, true)
        }
        
        let titleText = NSLocalizedString("AppID Customization", comment: "")
        let messageText = NSLocalizedString("Customize the AppID if required and press 'Confirm' to proceed.", comment: "")
        
        let alert = UIAlertController(
            title: titleText,
            message: messageText,
            preferredStyle: .alert
        )
        
        let team = try await AuthManager.shared.getAuthenticatedTeam()
        debugLog("[PipelineHandler] resolveBundleIDOverride: initialBundleID='\(initialBundleID)', teamID='\(team.identifier)', isAuthenticated=\(AuthManager.shared.isAuthenticated)")
        let teamID = team.identifier
        guard !teamID.isEmpty else {
            debugLog("[PipelineHandler] resolveBundleIDOverride FAILED: teamID is empty")
            throw OperationError.invalidParameters("Active developer team identifier is empty.")
        }
        let cleanInitialID: String = {
            let trimmed = initialBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            let base: String
            if !teamID.isEmpty && trimmed.hasSuffix(".\(teamID)") {
                base = String(trimmed.dropLast((".\(teamID)").count))
            } else {
                base = trimmed
            }
            let sanitized = InfoPlistParser.sanitizeBundleID(base)
            verboseLog("[PipelineHandler] cleanInitialID: trimmed='\(trimmed)', base='\(base)', sanitized='\(sanitized)'")
            return sanitized
        }()

        let checkboxView = AppendTeamIDCheckboxView(isChecked: true, teamID: teamID)
        checkboxView.translatesAutoresizingMaskIntoConstraints = false

        alert.addTextField { textField in
            let initialText = !teamID.isEmpty ? "\(cleanInitialID).\(teamID)" : cleanInitialID
            verboseLog("[PipelineHandler] resolveBundleIDOverride: setting textField.text='\(initialText)'")
            textField.text = initialText
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
            textField.clearButtonMode = .whileEditing
            checkboxView.attach(to: textField, teamID: teamID)
        }
        
        alert.addTextField { textField in
            textField.isUserInteractionEnabled = false
        }
        
        _ = alert.view
        if let tf1 = alert.textFields?.first, let tf1View = tf1.superview {
            tf1View.layer.cornerRadius = 20
            tf1View.layer.cornerCurve = .continuous
            tf1View.layer.maskedCorners = [
                .layerMinXMinYCorner,
                .layerMaxXMinYCorner,
                .layerMinXMaxYCorner,
                .layerMaxXMaxYCorner
            ]
            tf1View.layer.masksToBounds = true
            tf1View.clipsToBounds = true
            
            // Clear outer table grouping container so it doesn't draw flat bottom edges
            tf1View.superview?.backgroundColor = .clear
            tf1View.superview?.layer.borderWidth = 0
            tf1View.superview?.layer.borderColor = UIColor.clear.cgColor
        }
        
        if (alert.textFields?.count ?? 0) >= 2,
           let tf1 = alert.textFields?.first,
           let tf2 = alert.textFields?[1],
           let container = tf2.superview {
            tf2.isHidden = true
            container.backgroundColor = .clear
            container.layer.borderWidth = 0
            container.layer.borderColor = UIColor.clear.cgColor
            
            for subview in container.subviews where subview !== checkboxView && subview !== tf2 {
                subview.isHidden = true
                subview.alpha = 0
            }
            
            container.addSubview(checkboxView)
            NSLayoutConstraint.activate([
                checkboxView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
                checkboxView.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
                checkboxView.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
        }
        
        return await withCheckedContinuation { continuation in
            let okAction = UIAlertAction(title: NSLocalizedString("Confirm", comment: ""), style: .default) { _ in
                let baseID = checkboxView.cleanBaseID()
                let customID = InfoPlistParser.sanitizeBundleID(!baseID.isEmpty ? baseID : cleanInitialID)
                let appendTeamID = checkboxView.isChecked
                debugLog("[PipelineHandler] resolveBundleIDOverride confirmed: baseID='\(baseID)', customID='\(customID)', appendTeamID=\(appendTeamID)")
                continuation.resume(returning: (customID, appendTeamID))
            }
            
            let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
                continuation.resume(returning: nil)
            }
            alert.addAction(cancelAction)
            alert.addAction(okAction)
            presenter.present(alert, animated: true)
        }
    }


    @MainActor
    func resolveAppGroupMismatch(originalGroup: String, correctedGroup: String) async throws -> AppGroupResolution {
        guard let presenter = self.activePresenter else {
            return .correctAndProceed(correctedGroup)
        }
        
        let title = NSLocalizedString("App Group Discrepancy", comment: "")
        let message = String(format: NSLocalizedString("The app group '%@' does not match the app's bundle ID casing. Would you like to correct it to '%@'?", comment: ""), originalGroup, correctedGroup)
        
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            
            alert.addAction(UIAlertAction(title: NSLocalizedString("Correct & Proceed", comment: ""), style: .default) { _ in
                continuation.resume(returning: .correctAndProceed(correctedGroup))
            })
            
            alert.addAction(UIAlertAction(title: NSLocalizedString("Keep Original", comment: ""), style: .destructive) { _ in
                continuation.resume(returning: .keepOriginal(originalGroup))
            })
            
            alert.addAction(UIAlertAction(title: UIAlertAction.cancel.title, style: .cancel) { _ in
                continuation.resume(returning: .keepOriginal(originalGroup))
            })
            
            presenter.present(alert, animated: true)
        }
    }

    @MainActor
    func resolveAppIconCustomization(appName: String) async throws -> URL? {
        guard let presenter = self.activePresenter else {
            return nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            let title = NSLocalizedString("Customize App Icon", comment: "")
            let message = String(format: NSLocalizedString("Would you like to choose a custom icon for '%@' or keep the original icon?", comment: ""), appName)

            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)

            alert.addAction(UIAlertAction(title: NSLocalizedString("Choose from Photos", comment: ""), style: .default) { _ in
                #if !os(tvOS)
                let pickerDelegate = ImagePickerDelegateHandler { image in
                    guard let image = image,
                          let icon = image.resizing(toFill: CGSize(width: 256, height: 256)),
                          let iconData = icon.pngData() else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("CustomIcon_\(UUID().uuidString).png")
                    do {
                        try iconData.write(to: tempURL, options: .atomic)
                        continuation.resume(returning: tempURL)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } onCancel: {
                    continuation.resume(returning: nil)
                }

                let imagePicker = UIImagePickerController()
                imagePicker.allowsEditing = true
                imagePicker.delegate = pickerDelegate
                objc_setAssociatedObject(imagePicker, "pickerDelegate", pickerDelegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                presenter.present(imagePicker, animated: true)
                #else
                TVWebFileTransferManager.shared.startImport(
                    acceptedExtensions: ["png", "jpg", "jpeg"],
                    title: "Upload Custom App Icon",
                    presentingVC: presenter
                ) { fileURL in
                    guard let fileURL = fileURL,
                          let data = try? Data(contentsOf: fileURL),
                          let image = UIImage(data: data),
                          let icon = image.resizing(toFill: CGSize(width: 256, height: 256)),
                          let iconData = icon.pngData() else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("CustomIcon_\(UUID().uuidString).png")
                    do {
                        try iconData.write(to: tempURL, options: .atomic)
                        continuation.resume(returning: tempURL)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                #endif
            })

            alert.addAction(UIAlertAction(title: NSLocalizedString("Keep Original Icon", comment: ""), style: .default) { _ in
                continuation.resume(returning: nil)
            })

            alert.addAction(UIAlertAction(title: UIAlertAction.cancel.title, style: .cancel) { _ in
                continuation.resume(throwing: OperationError.cancelled)
            })

            presenter.present(alert, animated: true)
        }
    }

    @MainActor
    func resolveProvisioningProfileCustomization(appName: String, bundleID: String) async throws -> ProfileCustomizationChoice? {
        guard let presenter = self.activePresenter else {
            return .defaultProfile
        }

        let allProfiles = ProfileManager.shared.getAllLocalProfiles()
        guard !allProfiles.isEmpty else {
            return .defaultProfile
        }

        return try await withCheckedThrowingContinuation { continuation in
            let title = NSLocalizedString("Select Provisioning Profile", comment: "")
            let message = String(format: NSLocalizedString("Choose a provisioning profile for '%@' (%@), or use the default automatic profile.", comment: ""), appName, bundleID)

            let alert = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)

            alert.addAction(UIAlertAction(title: NSLocalizedString("Default (Automatic Team Profile)", comment: ""), style: .default) { _ in
                continuation.resume(returning: .defaultProfile)
            })

            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none

            for profile in allProfiles {
                let isReady = ProfileManager.shared.isProfileReadyToSign(profile)
                let certInfo = isReady ? "✓ Ready" : (profile.expirationDate < Date() ? "Expired" : "No Key")
                let profileTitle = "\(profile.name) (\(certInfo), exp: \(formatter.string(from: profile.expirationDate)))"

                alert.addAction(UIAlertAction(title: profileTitle, style: .default) { _ in
                    continuation.resume(returning: .profile(profile))
                })
            }

            alert.addAction(UIAlertAction(title: UIAlertAction.cancel.title, style: .cancel) { _ in
                continuation.resume(throwing: OperationError.cancelled)
            })

            #if !os(tvOS)
            if let popover = alert.popoverPresentationController {
                popover.sourceView = presenter.view
                popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            #endif

            presenter.present(alert, animated: true)
        }
    }
}

private final class ImagePickerDelegateHandler: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let onSelect: (UIImage?) -> Void
    let onCancel: () -> Void

    init(onSelect: @escaping (UIImage?) -> Void, onCancel: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        picker.dismiss(animated: true) {
            self.onSelect(image)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true) {
            self.onCancel()
        }
    }
}
