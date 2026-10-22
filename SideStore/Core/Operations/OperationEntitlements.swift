//
//  OperationEntitlements.swift
//  SideStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

import Foundation
import SideSign

struct OperationEntitlements {
    static let defaultAdditionalEntitlements: [ALTEntitlement: any Sendable] = [
        .increasedDebuggingMemoryLimit  : ALTEntitlement.increasedDebuggingMemoryLimit,
        .increasedMemoryLimit           : ALTEntitlement.increasedMemoryLimit,
        .extendedVirtualAddressing      : ALTEntitlement.extendedVirtualAddressing
    ]
}
