//
//  TextCollectionReusableView.swift
//  AltStore
//
//  Created by Riley Testut on 3/23/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit

class TextCollectionReusableView: UICollectionReusableView
{
    @IBOutlet var textLabel: UILabel!
    
    @IBOutlet var topLayoutConstraint: NSLayoutConstraint!
    @IBOutlet var bottomLayoutConstraint: NSLayoutConstraint!
    @IBOutlet var leadingLayoutConstraint: NSLayoutConstraint!
    @IBOutlet var trailingLayoutConstraint: NSLayoutConstraint!
}
