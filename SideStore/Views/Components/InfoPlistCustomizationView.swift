//
//  InfoPlistCustomizationView.swift
//  SideStore
//
//  Created by Magesh K on 13/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import UIKit

public struct InfoPlistCustomizationView: View {
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
            style: .dialog,
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

extension InfoPlistCustomizationView {
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
            var hostingController: UIHostingController<AnyView>?

            let coreView = InfoPlistCustomizationCoreView(
                style: .dialog,
                targets: targets,
                initialBundleID: initialBundleID,
                appendTeamID: appendTeamID,
                installedAppIdentities: installedAppIdentities,
                teamID: teamID,
                onProceed: { modifiedPlists, shouldAppend in
                    hostingController?.dismiss(animated: true) {
                        continuation.resume(returning: (modifiedPlists, shouldAppend))
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
