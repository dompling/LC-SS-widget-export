//
//  InfoPlistCustomizationSheetView.swift
//  SideStore
//
//  Created by Magesh K on 13/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import UIKit

public struct InfoPlistCustomizationSheetView: View {
    private typealias RawPlistType = InfoPlistCustomizationCoreView.RawPlistType
    private typealias RawPlistEntry = InfoPlistCustomizationCoreView.RawPlistEntry

    public let initialPlist: [String: any Sendable]
    public let initialBundleID: String
    public let appendTeamID: Bool
    public let installedAppIdentities: [String: String]
    public let teamID: String
    public let onProceed: ([String: any Sendable], Bool) -> Void
    public let onCancel: () -> Void

    public init(
        initialPlist: [String: any Sendable],
        initialBundleID: String,
        appendTeamID: Bool = true,
        installedAppIdentities: [String: String] = [:],
        teamID: String = "",
        onProceed: @escaping ([String: any Sendable], Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialPlist = initialPlist
        self.initialBundleID = initialBundleID
        self.appendTeamID = appendTeamID
        self.installedAppIdentities = installedAppIdentities
        self.teamID = teamID
        self.onProceed = onProceed
        self.onCancel = onCancel
    }

    public var body: some View {
        InfoPlistCustomizationCoreView(
            style: .sheet,
            initialPlist: initialPlist,
            initialBundleID: initialBundleID,
            appendTeamID: appendTeamID,
            installedAppIdentities: installedAppIdentities,
            teamID: teamID,
            onProceed: onProceed,
            onCancel: onCancel
        )
    }
}

private final class SheetDismissDelegate: NSObject, UIAdaptivePresentationControllerDelegate {
    private var isResumed = false
    var onDismiss: (() -> Void)?

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        resumeOnce()
    }

    func resumeOnce() {
        guard !isResumed else { return }
        isResumed = true
        onDismiss?()
    }
}

private final class SheetHostingController<Content: View>: UIHostingController<Content> {
    var dismissDelegate: UIAdaptivePresentationControllerDelegate?
}

extension InfoPlistCustomizationSheetView {
    @MainActor
    public static func present(
        from presenter: UIViewController,
        targets: [InfoPlistTarget],
        initialBundleID: String,
        appendTeamID: Bool = true,
        installedAppIdentities: [String: String] = [:],
        teamID: String = ""
    ) async -> (modifiedPlists: [String: [String: any Sendable]], appendTeamID: Bool)? {
        await withCheckedContinuation { continuation in
            var hostingController: SheetHostingController<AnyView>?
            let dismissDelegate = SheetDismissDelegate()

            var hasResumed = false
            let safeResume: ((modifiedPlists: [String: [String: any Sendable]], appendTeamID: Bool)?) -> Void = { result in
                guard !hasResumed else { return }
                hasResumed = true
                dismissDelegate.resumeOnce()
                continuation.resume(returning: result)
            }

            dismissDelegate.onDismiss = {
                safeResume(nil)
            }

            let coreView = InfoPlistCustomizationCoreView(
                style: .sheet,
                targets: targets,
                initialBundleID: initialBundleID,
                appendTeamID: appendTeamID,
                installedAppIdentities: installedAppIdentities,
                teamID: teamID,
                onProceed: { modifiedPlists, shouldAppend in
                    hostingController?.dismiss(animated: true) {
                        safeResume((modifiedPlists, shouldAppend))
                    }
                },
                onCancel: {
                    hostingController?.dismiss(animated: true) {
                        safeResume(nil)
                    }
                }
            )

            let controller = SheetHostingController(rootView: AnyView(coreView))
            controller.dismissDelegate = dismissDelegate
            controller.modalPresentationStyle = .pageSheet
            controller.presentationController?.delegate = dismissDelegate
            if let sheet = controller.sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = true
            }
            hostingController = controller

            presenter.present(controller, animated: true)
        }
    }

    @MainActor
    public static func present(
        from presenter: UIViewController,
        initialPlist: [String: any Sendable],
        initialBundleID: String,
        appendTeamID: Bool = true,
        installedAppIdentities: [String: String] = [:],
        teamID: String = ""
    ) async -> (modifiedPlist: [String: any Sendable], appendTeamID: Bool)? {
        let target = InfoPlistTarget(
            id: initialBundleID,
            initialPlist: initialPlist
        )
        guard let result = await present(
            from: presenter,
            targets: [target],
            initialBundleID: initialBundleID,
            appendTeamID: appendTeamID,
            installedAppIdentities: installedAppIdentities,
            teamID: teamID
        ) else { return nil }

        let plist = result.modifiedPlists[initialBundleID] ?? initialPlist
        return (plist, result.appendTeamID)
    }
}
