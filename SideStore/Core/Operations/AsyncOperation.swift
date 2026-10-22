//
//  AsyncOperation.swift
//  SideStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

@preconcurrency import UIKit

protocol AsyncOperation<T>: AnyObject, ProgressReporting, OperationLogging {
    associatedtype T
    
    var isCancelled: Bool { get }

    @discardableResult
    func execute(parentProgress: Progress?) async throws -> T
    func cancel()
}

class BaseOperation<Context: OperationContext, Result>: NSObject, AsyncOperation, @unchecked Sendable{
    typealias T = Result

    private(set) var progress: Progress!
    private(set) var context: Context!
    
    private(set) var isCancelled = false
    fileprivate let lock = NSLock()
    

    var totalUnitCount: Int64 { 100 }
    
    init(context: Context) throws {
        if Self.self === BaseOperation.self {
            throw AbstractClassError.abstractInitializerInvoked
        }
        super.init()        
        self.context = context
        self.progress = Progress.discreteProgress(totalUnitCount: self.totalUnitCount)
        self.progress.cancellationHandler = { [weak self] in self?.cancel() }
    }
    
    func setProgress(_ completedUnitCount: Int64) {
        let previous = self.progress.completedUnitCount
        self.progress.completedUnitCount = completedUnitCount
        verboseLog("[\(String(describing: type(of: self)))] Progress updated: \(previous) -> \(completedUnitCount) (total: \(self.progress.totalUnitCount))")
    }
    
    func operationStep() throws -> any OperationStep {
        throw AbstractClassError.abstractMethodInvoked
    }
    
    func executePreconditionCheck(parentProgress: Progress?) async throws {
        let className = String(describing: type(of: self))
        debugLog("[\(className)] executePreconditionCheck() started")
        defer { debugLog("[\(className)] executePreconditionCheck() completed") }
        
        if let parentProgress = parentProgress {
            let step = try self.operationStep()
            if try !self.context.attachProgressSlot(for: step, childProgress: self.progress, parentProgress: parentProgress) {
                let unitCount = try self.context.consumeWeight(for: step)
                if unitCount > 0 {
                    verboseLog("[\(className)] Adding child progress to parent with weight: \(unitCount) (parent total: \(parentProgress.totalUnitCount))")
                    parentProgress.addChild(self.progress, withPendingUnitCount: unitCount)
                }
            }
        }
        if self.isCancelled {
            throw OperationError.cancelled
        }
        if let error = self.context.error {
            throw error
        }
    }
    
    @discardableResult
    func execute(parentProgress: Progress?) async throws -> Result
    {
        throw AbstractClassError.abstractMethodInvoked
    }
    
    @discardableResult
    func execute() async throws -> Result {
        try await self.execute(parentProgress: nil)
    }
    
    func cancel() {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.isCancelled = true
    }
}

class BasePipelineOperation<Context: OperationContext, Result>: BaseOperation<Context, Result>, @unchecked Sendable {
    override func operationStep() throws -> any OperationStep {
        guard let step = PipelineStep.step(for: self) else {
            throw OperationError.invalidParameters("Missing PipelineStep mapping for \(type(of: self))")
        }
        return step
    }
}

class BaseStandaloneOperation<Context: OperationContext, Result>: BaseOperation<Context, Result>, @unchecked Sendable {
    override func operationStep() throws -> any OperationStep {
        guard let step = StandaloneStep.step(for: type(of: self)) else {
            throw OperationError.invalidParameters("Missing StandaloneStep mapping for \(type(of: self))")
        }
        return step
    }
}
