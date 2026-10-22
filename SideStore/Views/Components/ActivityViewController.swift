//
//  ActivityViewController.swift
//  SideStore
//
//  Created by Magesh K on 12/09/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

#if !os(tvOS)
import UIKit
import SwiftUI

struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    init(activityItems: [Any], applicationActivities: [UIActivity]? = nil) {
        self.activityItems = activityItems
        self.applicationActivities = applicationActivities
    }

    init(items: [Any], applicationActivities: [UIActivity]? = nil) {
        self.activityItems = items
        self.applicationActivities = applicationActivities
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


#else
import UIKit
import SwiftUI

struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [Any]? = nil

    init(activityItems: [Any], applicationActivities: [Any]? = nil) {
        self.activityItems = activityItems
        self.applicationActivities = applicationActivities
    }

    init(items: [Any], applicationActivities: [Any]? = nil) {
        self.activityItems = items
        self.applicationActivities = applicationActivities
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        if let fileURL = activityItems.first(where: { $0 is URL }) as? URL {
            DispatchQueue.main.async {
                TVWebFileTransferManager.shared.startExport(fileURL: fileURL, title: "Export File", presentingVC: vc)
            }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}


#endif
