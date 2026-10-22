//
//  RefreshGroup.swift
//  AltStore
//
//  Created by Riley Testut on 6/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData
import SideSign

final class RefreshGroup: NSObject
{
    let dbContext: NSManagedObjectContext
    let sharedContext: SharedPipelineContext
    let progress = Progress.discreteProgress(totalUnitCount: 100)
    var error: Error?
    var isCellularRefreshGroup: Bool = false
    let operationStartTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    
    var completionHandler: (([String: Result<InstalledApp, Error>]) -> Void)?
    var beginInstallationHandler: ((InstalledApp) -> Void)?
        
    private(set) var results = [String: Result<InstalledApp, Error>]()
    
    // Keep strong references to managed object contexts
    // so they don't die out from under us.
    private(set) var retainedContexts = Set<NSManagedObjectContext>()
    
    var activeTask: Task<Void, Never>?
    private let lock = NSLock()
    
    init(dbContext: NSManagedObjectContext, sharedContext: SharedPipelineContext = SharedPipelineContext())
    {
        self.dbContext = dbContext
        self.sharedContext = sharedContext
        super.init()
    }
    
    func set(_ result: Result<InstalledApp, Error>, forAppWithBundleIdentifier bundleIdentifier: String)
    {
        self.lock.withLock {
            self.results[bundleIdentifier] = result
            
            switch result
            {
            case .failure: break
            case .success(let installedApp):
                guard let context = installedApp.managedObjectContext else { break }
                self.retainedContexts.insert(context)
            }
        }
    }
    
    func cancel()
    {
        self.activeTask?.cancel()
    }
}
