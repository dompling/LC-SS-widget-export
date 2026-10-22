//
//  AbstractClassError.swift
//  SideStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation

public enum AbstractClassError: Error {
    case abstractInitializerInvoked
    case abstractMethodInvoked
}
