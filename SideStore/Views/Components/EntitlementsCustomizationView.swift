//
//  EntitlementsCustomizationView.swift
//  SideStore
//
//  Created by Magesh K on 13/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import UIKit
import SideSign

public struct EntitlementsCustomizationView: View {
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
            style: .dialog,
            initialEntitlements: initialEntitlements,
            bundleID: bundleID,
            teamType: teamType,
            onProceed: onProceed,
            onCancel: onCancel
        )
    }
}

extension EntitlementsCustomizationView {
    @MainActor
    public static func present(
        from presenter: UIViewController,
        targets: [EntitlementsTarget],
        teamType: ALTTeamType
    ) async -> [String: [String: any Sendable]]? {
        await withCheckedContinuation { continuation in
            var hostingController: UIHostingController<AnyView>?

            let coreView = EntitlementsCustomizationCoreView(
                style: .dialog,
                targets: targets,
                teamType: teamType,
                onProceed: { modifiedTargets in
                    hostingController?.dismiss(animated: true) {
                        continuation.resume(returning: modifiedTargets)
                    }
                },
                onCancel: {
                    hostingController?.dismiss(animated: true) {
                        continuation.resume(returning: nil)
                    }
                }
            )

            let controller = UIHostingController(rootView: AnyView(coreView))
            controller.modalPresentationStyle = .overFullScreen
            controller.modalTransitionStyle = .crossDissolve
            controller.view.backgroundColor = .clear
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
