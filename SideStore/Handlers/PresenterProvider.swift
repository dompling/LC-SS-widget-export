//
//  PresenterProvider.swift
//  SideStore
//
//  Created by Magesh K on 4/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit

// yeah just coz we wanna reuse and not pollute other files 
// I am keeping this reusable typealias separate there in its own file
typealias PresenterProvider = @MainActor @Sendable () -> UIViewController?
