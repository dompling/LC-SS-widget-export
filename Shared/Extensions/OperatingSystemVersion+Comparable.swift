//
//  OperatingSystemVersion+Comparable.swift
//  AltStore
//
//  Created by Riley Testut on 11/15/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import Foundation

public extension OperatingSystemVersion {
    var stringValue: String {
        if patchVersion == 0 {
            return "\(majorVersion).\(minorVersion)"
        } else {
            return "\(majorVersion).\(minorVersion).\(patchVersion)"
        }
    }
}

extension OperatingSystemVersion
{
    public static func ==(lhs: OperatingSystemVersion, rhs: OperatingSystemVersion) -> Bool
    {
        return lhs.majorVersion == rhs.majorVersion && lhs.minorVersion == rhs.minorVersion && lhs.patchVersion == rhs.patchVersion
    }
    
    public static func <(lhs: OperatingSystemVersion, rhs: OperatingSystemVersion) -> Bool
    {
        if lhs.majorVersion != rhs.majorVersion {
            return lhs.majorVersion < rhs.majorVersion
        }
        if lhs.minorVersion != rhs.minorVersion {
            return lhs.minorVersion < rhs.minorVersion
        }
        return lhs.patchVersion < rhs.patchVersion
    }
}
