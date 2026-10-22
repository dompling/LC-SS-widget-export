//
//  UISwitch+tvOS.swift
//  SideStore
//
//  Created by Magesh K on 26/08/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

#if os(tvOS)
@preconcurrency import UIKit

public typealias UISwitch = UIControl

public extension UIControl {
    var isOn: Bool {
        get { self.isSelected }
        set { self.isSelected = newValue }
    }

    func setOn(_ on: Bool, animated: Bool) {
        self.isOn = on
    }
}
#endif
