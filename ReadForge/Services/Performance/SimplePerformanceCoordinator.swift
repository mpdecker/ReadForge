//
//  SimplePerformanceCoordinator.swift
//  ReadForge
//
//  Simplified performance management for document reader app
//

import Foundation
import UIKit

/// Simplified performance coordinator for basic monitoring
@MainActor
@Observable
final class SimplePerformanceCoordinator {
    
    // MARK: - Properties
    
    private var memoryWarningObserver: NSObjectProtocol?
    
    // MARK: - Public Interface
    
    /// Start basic performance monitoring
    func startMonitoring() {
        setupMemoryWarningObserver()
        ReadForgeLogger.debug(category: "Performance", message: "Performance monitoring started")
    }
    
    /// Stop performance monitoring
    func stopMonitoring() {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
            memoryWarningObserver = nil
        }
        ReadForgeLogger.debug(category: "Performance", message: "Performance monitoring stopped")
    }
    
    /// Check if heavy operations should be allowed
    func shouldAllowHeavyOperations() -> Bool {
        // Simple check - could be enhanced with battery/thermal monitoring if needed
        return true
    }
    
    /// Process large documents in chunks
    func processLargeDocument<T>(
        document: DocumentRecord,
        chunkSize: Int = 50,
        processor: @escaping (SectionRecord) async throws -> T
    ) async throws -> [T] {
        let sections = document.sections.sorted { $0.order < $1.order }
        var results: [T] = []
        
        // Process in chunks to avoid memory pressure
        for chunk in sections.chunked(into: chunkSize) {
            let chunkResults = try await withThrowingTaskGroup(of: T.self) { group in
                for section in chunk {
                    group.addTask {
                        try await processor(section)
                    }
                }
                
                var chunkResults: [T] = []
                for try await result in group {
                    chunkResults.append(result)
                }
                return chunkResults
            }
            results.append(contentsOf: chunkResults)
            
            // Small delay between chunks to be responsive
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        
        return results
    }
    
    // MARK: - Private Methods
    
    private func setupMemoryWarningObserver() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            ReadForgeLogger.performanceWarning(operation: "Memory Warning", issue: "System reported low memory")
            // Could trigger cache cleanup here if needed
        }
    }
}

// MARK: - Array Extension

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
