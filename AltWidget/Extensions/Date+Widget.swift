//
//  Date+Widget.swift
//  AltWidget
//
//  Created by Magesh K on 8/13/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation

extension Date {
    func numberOfCalendarDays(since date: Date) -> Int {
        let calendar = Calendar.current
        let startOfSelf = calendar.startOfDay(for: self)
        let startOfOther = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.day], from: startOfOther, to: startOfSelf)
        return components.day ?? 0
    }
}
