//
//  UIViewController+WebURL.swift
//  SideStore
//
//  Created by Magesh K on 26/08/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
#if !os(tvOS)
import SafariServices
#endif

public extension UIViewController {
    func openWebURL(_ url: URL, preferredTintColor: UIColor? = nil, animated: Bool = true, completion: (() -> Void)? = nil) {
        #if !os(tvOS)
        let webVC = self.makeWebViewController(for: url, preferredTintColor: preferredTintColor)
        self.present(webVC, animated: animated, completion: completion)
        #else
        UIApplication.shared.open(url, options: [:]) { _ in
            completion?()
        }
        #endif
    }

    func makeWebViewController(for url: URL, preferredTintColor: UIColor? = nil) -> UIViewController {
        #if !os(tvOS)
        let safariViewController = SFSafariViewController(url: url)
        if let preferredTintColor {
            safariViewController.preferredControlTintColor = preferredTintColor
        }
        return safariViewController
        #else
        let fallbackVC = UIViewController()
        Task { @MainActor in
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        return fallbackVC
        #endif
    }
}
