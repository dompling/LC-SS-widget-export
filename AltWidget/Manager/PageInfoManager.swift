//
//  PageInfoManager.swift
//  AltStore
//
//  Created by Magesh K on 11/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import Foundation

// TODO: See if we can persist these values instead of keeping in memory to prevent memory leaks
//       Possible ways: Userdefaults.standard - set/get ?
class PageInfoManager {
    static var shared = PageInfoManager()
    private var pageInfoMap: [String: NavigationEvent] = [:]
    
    private init() {}
    
    private func getKey(forWidgetKind kind: String, forWidgetID id: Int) -> String{
        return "\(kind)@\(id)"
    }
    
    func setPageInfo(forWidgetKind kind: String, forWidgetID id: Int, value: NavigationEvent?) {
        let key = getKey(forWidgetKind: kind, forWidgetID: id)
        verboseLog("[PageInfoManager] setPageInfo for \(key): direction=\(String(describing: value?.direction)), consumed=\(String(describing: value?.consumed))")
        pageInfoMap[key] = value
    }
    
    func getPageInfo(forWidgetKind kind: String, forWidgetID id: Int) -> NavigationEvent? {
        let key = getKey(forWidgetKind: kind, forWidgetID: id)
        let event = pageInfoMap[key]
        verboseLog("[PageInfoManager] getPageInfo for \(key) -> \(event != nil ? "found" : "nil")")
        return event
    }

    func popPageInfo(forWidgetKind kind: String, forWidgetID id: Int) -> NavigationEvent? {
        let key = getKey(forWidgetKind: kind, forWidgetID: id)
        verboseLog("[PageInfoManager] popPageInfo for \(key)")
        return pageInfoMap.removeValue(forKey: key)
    }

    func clearAll() {
        verboseLog("[PageInfoManager] clearAll called")
        pageInfoMap.removeAll()
    }
}
