//
//  EntitlementsCustomizationSheetView.swift
//  SideStore
//
//  Created by Magesh K on 13/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import UIKit
import SideSign

public struct EntitlementsCustomizationSheetView: View {
    public let initialEntitlements: [String: any Sendable]
    public let bundleID: String
    public let teamType: ALTTeamType
    public let onProceed: ([String: any Sendable]) -> Void
    public let onCancel: () -> Void

    public init(
        initialEntitlements: [String: any Sendable],
        bundleID: String,
        teamType: ALTTeamType,
        onProceed: @escaping ([String: any Sendable]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialEntitlements = initialEntitlements
        self.bundleID = bundleID
        self.teamType = teamType
        self.onProceed = onProceed
        self.onCancel = onCancel
    }

    public var body: some View {
        EntitlementsCustomizationCoreView(
            style: .sheet,
            initialEntitlements: initialEntitlements,
            bundleID: bundleID,
            teamType: teamType,
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

extension EntitlementsCustomizationSheetView {
    @MainActor
    public static func present(
        from presenter: UIViewController,
        targets: [EntitlementsTarget],
        teamType: ALTTeamType
    ) async -> [String: [String: any Sendable]]? {
        await withCheckedContinuation { continuation in
            var hostingController: SheetHostingController<AnyView>?
            let dismissDelegate = SheetDismissDelegate()

            var hasResumed = false
            let safeResume: ([String: [String: any Sendable]]?) -> Void = { result in
                guard !hasResumed else { return }
                hasResumed = true
                dismissDelegate.resumeOnce()
                continuation.resume(returning: result)
            }

            dismissDelegate.onDismiss = {
                safeResume(nil)
            }

            let coreView = EntitlementsCustomizationCoreView(
                style: .sheet,
                targets: targets,
                teamType: teamType,
                onProceed: { modifiedTargets in
                    hostingController?.dismiss(animated: true) {
                        safeResume(modifiedTargets)
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
            controller.presentationController?.delegate = dismissDelegate
            controller.modalPresentationStyle = .pageSheet
            hostingController = controller

            presenter.present(controller, animated: true)
        }
    }

    @MainActor
    public static func present(
        from presenter: UIViewController,
        initialEntitlements: [String: any Sendable],
        bundleID: String,
        teamType: ALTTeamType
    ) async -> [String: any Sendable]? {
        let target = EntitlementsTarget(
            id: bundleID,
            name: bundleID,
            isExtension: false,
            initialEntitlements: initialEntitlements
        )
        let result = await present(from: presenter, targets: [target], teamType: teamType)
        return result?[bundleID]
    }
}
