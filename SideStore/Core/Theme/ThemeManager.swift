//
//  ThemeManager.swift
//  SideStore
//
//  Created by Magesh K on 9/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit
import Combine

public struct ThemePreset: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let hex: String
    
    public var color: UIColor {
        UIColor(hex: hex) ?? .defaultAltPrimary
    }
    
    public static let presets: [ThemePreset] = [
        ThemePreset(id: "classic", name: "SideStore Teal", hex: "#19D3B5"),
        ThemePreset(id: "neonViolet", name: "Neon Violet", hex: "#8B5CF6"),
        ThemePreset(id: "sunsetCrimson", name: "Sunset Crimson", hex: "#EF4444"),
        ThemePreset(id: "sapphireBlue", name: "Sapphire Blue", hex: "#3B82F6"),
        ThemePreset(id: "cyberpunkGold", name: "Cyberpunk Gold", hex: "#F59E0B"),
        ThemePreset(id: "emeraldMint", name: "Emerald Mint", hex: "#10B981"),
        ThemePreset(id: "electricPink", name: "Electric Pink", hex: "#EC4899")
    ]
}

public final class ThemeManager: ObservableObject {
    public static let shared = ThemeManager()
    public static let themeDidChangeNotification = Notification.Name("SideStoreThemeDidChangeNotification")

    private static let userDefaultsKey = "userCustomThemeHex"

    @Published public var primaryColor: UIColor {
        didSet {
            UserDefaults.standard.set(primaryColor.hexString, forKey: Self.userDefaultsKey)
            NotificationCenter.default.post(name: Self.themeDidChangeNotification, object: primaryColor)
            DispatchQueue.main.async {
                if let window = UIApplication.alt_shared?.alt_keyWindow {
                    window.tintColor = self.primaryColor
                }
            }
        }
    }

    private init() {
        if let hex = UserDefaults.standard.string(forKey: Self.userDefaultsKey),
           let color = UIColor(hex: hex) {
            self.primaryColor = color
        } else {
            self.primaryColor = .defaultAltPrimary
        }
    }

    public func resetToDefault() {
        self.primaryColor = .defaultAltPrimary
        UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
    }
}

public extension UIColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if hexSanitized.hasPrefix("#") {
            hexSanitized.remove(at: hexSanitized.startIndex)
        }

        var rgbValue: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgbValue) else { return nil }

        let r, g, b, a: CGFloat
        if hexSanitized.count == 6 {
            r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgbValue & 0x0000FF) / 255.0
            a = 1.0
        } else if hexSanitized.count == 8 {
            r = CGFloat((rgbValue & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgbValue & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgbValue & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgbValue & 0x000000FF) / 255.0
        } else {
            return nil
        }

        self.init(red: r, green: g, blue: b, alpha: a)
    }

    var rgbComponents: (r: Int, g: Int, b: Int) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int(r * 255), Int(g * 255), Int(b * 255))
    }

    var hslComponents: (h: Int, s: Int, l: Int) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)

        let maxVal = max(r, max(g, b))
        let minVal = min(r, min(g, b))
        let delta = maxVal - minVal

        var h: CGFloat = 0
        var s: CGFloat = 0
        let l: CGFloat = (maxVal + minVal) / 2.0

        if delta != 0 {
            s = l > 0.5 ? delta / (2.0 - maxVal - minVal) : delta / (maxVal + minVal)

            if maxVal == r {
                h = (g - b) / delta + (g < b ? 6 : 0)
            } else if maxVal == g {
                h = (b - r) / delta + 2
            } else {
                h = (r - g) / delta + 4
            }
            h /= 6.0
        }

        return (Int(h * 360), Int(s * 100), Int(l * 100))
    }
}
