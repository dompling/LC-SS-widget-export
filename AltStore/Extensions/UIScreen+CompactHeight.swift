//
//  UIScreen+CompactHeight.swift
//  AltStore
//
//  Created by Riley Testut on 9/6/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit

extension UIScreen
{
    var isExtraCompactHeight: Bool {
        return self.fixedCoordinateSpace.bounds.height < 600
    }
}
