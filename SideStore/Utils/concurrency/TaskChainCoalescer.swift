//
//  TaskChainCoalescer.swift
//  SideStore
//
//  Created by Magesh K on 31/7/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation

/*
 A coalescing actor that folds duplicate concurrent requests into a single task execution.
 All concurrent requests awaiting the same key will block on the same task, and receive 
 the identical result simultaneously.
 */
actor TaskChainCoalescer {
    static let shared = TaskChainCoalescer()
    
    private var activeTasks = [String: Task<Any, Error>]()
    
    func coalesce<T: Sendable>(key: String, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        if let existingTask = activeTasks[key] {
            let result = try await existingTask.value
            return result as! T
        }
        
        let newTask = Task<Any, Error> {
            let result = try await operation()
            return result
        }
        
        activeTasks[key] = newTask
        
        defer {
            self.removeTask(key: key)
        }
        
        let result = try await newTask.value
        return result as! T
    }
    
    private func removeTask(key: String) {
        activeTasks.removeValue(forKey: key)
    }
}






actor TaskChainCoalescerWithProgress {
    static let shared = TaskChainCoalescerWithProgress()
    
    private class CoalescedEntry {
        let task: Task<Any, Error>
        var progressHandlers: [@Sendable (Int64) -> Void]
        
        init(task: Task<Any, Error>, progressHandlers: [@Sendable (Int64) -> Void]) {
            self.task = task
            self.progressHandlers = progressHandlers
        }
    }
    
    private var activeTasks = [String: CoalescedEntry]()
    
    func coalesce<T: Sendable>(
        key: String,
        onProgress: (@Sendable (Int64) -> Void)? = nil,
        _ operation: @escaping @Sendable (_ reportProgress: @escaping @Sendable (Int64) -> Void) async throws -> T
    ) async throws -> T {
        if let existing = activeTasks[key] {
            if let onProgress = onProgress {
                existing.progressHandlers.append(onProgress)
            }
            let result = try await existing.task.value
            return result as! T
        }
        
        var initialHandlers = [@Sendable (Int64) -> Void]()
        if let onProgress = onProgress {
            initialHandlers.append(onProgress)
        }
        
        let newTask = Task<Any, Error> {
            let result = try await operation { progress in
                Task {
                    await self.broadcastProgress(key: key, progress: progress)
                }
            }
            return result
        }
        
        activeTasks[key] = CoalescedEntry(task: newTask, progressHandlers: initialHandlers)
        
        defer {
            self.removeTask(key: key)
        }
        
        let result = try await newTask.value
        return result as! T
    }
    
    func broadcastProgress(key: String, progress: Int64) {
        guard let entry = activeTasks[key] else { return }
        for handler in entry.progressHandlers {
            handler(progress)
        }
    }
    
    private func removeTask(key: String) {
        activeTasks.removeValue(forKey: key)
    }
}
