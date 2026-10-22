//
//  ForwardingNavigationController.swift
//  AltStore
//
//  Created by Riley Testut on 10/24/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit

final class ForwardingNavigationController: UINavigationController
{
#if !os(tvOS)
    override var childForStatusBarStyle: UIViewController? {
        return self.topViewController
    }
    
    override var childForStatusBarHidden: UIViewController? {
        return self.topViewController
    }
#endif
}
