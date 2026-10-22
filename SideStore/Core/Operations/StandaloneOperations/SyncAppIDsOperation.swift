//
//  SyncAppIDsOperation.swift
//  SideStore
//
//  Created by Magesh K on 31/7/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import CoreData
import SideSign

final class SyncAppIDsOperation: BaseStandaloneOperation<StandaloneOperationContext, Void>, @unchecked Sendable {
    
    override func execute(parentProgress: Progress?) async throws -> Void {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[SyncAppIDsOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[SyncAppIDsOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        
        let team = try await AuthManager.shared.getAuthenticatedTeam()
        
        self.setProgress(10)
        
        let dbContext = self.context.dbBackgroundContext
        
        let fetchedAppIDs = try await TaskChainCoalescer.shared.coalesce(key: "fetch_app_ids_\(team.identifier)") {
            try await DeveloperPortalProxy.shared.fetchAppIDs(team: team)
        }
        self.setProgress(50)
        
        try await dbContext.perform {
            try self.syncAppIDs(fetchedAppIDs, team: team, in: dbContext)
            if dbContext.hasChanges {
                try dbContext.save()
            }
        }
        self.setProgress(100)
    }
    
    private func syncAppIDs(_ fetchedAppIDs: [ALTAppID], team: ALTTeam, in dbContext: NSManagedObjectContext) throws {
        guard let team = Team.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(Team.identifier), team.identifier), in: dbContext) else {
            throw OperationError.notAuthenticated
        }
        
        var uniqueFetchedAppIDs = [ALTAppID]()
        var seenIdentifiers = Set<String>()
        for appID in fetchedAppIDs {
            if !seenIdentifiers.contains(appID.identifier) {
                seenIdentifiers.insert(appID.identifier)
                uniqueFetchedAppIDs.append(appID)
            }
        }
        
        let fetchedIdentifiers = uniqueFetchedAppIDs.map { $0.identifier }
        
        let deletedAppIDsRequest = AppID.fetchRequest() as NSFetchRequest<AppID>
        deletedAppIDsRequest.predicate = NSPredicate(format: "%K == %@ AND NOT (%K IN %@)",
                                                     #keyPath(AppID.team), team,
                                                     #keyPath(AppID.identifier), fetchedIdentifiers)
        
        let deletedAppIDs = try dbContext.fetch(deletedAppIDsRequest)
        deletedAppIDs.forEach { dbContext.delete($0) }
        
        let existingAppIDsRequest = AppID.fetchRequest() as NSFetchRequest<AppID>
        existingAppIDsRequest.predicate = NSPredicate(format: "%K == %@ AND %K IN %@",
                                                      #keyPath(AppID.team), team,
                                                      #keyPath(AppID.identifier), fetchedIdentifiers)
        let existingAppIDs = try dbContext.fetch(existingAppIDsRequest)
        let existingAppIDsByIdentifier = Dictionary(uniqueKeysWithValues: existingAppIDs.map { ($0.identifier, $0) })
        
        var appIDs = [AppID]()
        let startProgress = self.progress.completedUnitCount
        let endProgress: Int64 = 95
        let range = endProgress - startProgress
        let count = uniqueFetchedAppIDs.count
        
        for (index, altAppID) in uniqueFetchedAppIDs.enumerated() {
            if range > 0 {
                let percent = startProgress + Int64(Double(index + 1) / Double(count) * Double(range))
                self.setProgress(percent)
            }
            
            if let existingAppID = existingAppIDsByIdentifier[altAppID.identifier] {
                existingAppID.name = altAppID.name
                existingAppID.bundleIdentifier = altAppID.bundleIdentifier
                existingAppID.features = altAppID.features.reduce(into: [:]) { $0[$1.key] = $1.value }
                existingAppID.expirationDate = altAppID.expirationDate
                appIDs.append(existingAppID)
            } else {
                let newAppID = AppID(altAppID, team: team, context: dbContext)
                appIDs.append(newAppID)
            }
        }
    }
}
