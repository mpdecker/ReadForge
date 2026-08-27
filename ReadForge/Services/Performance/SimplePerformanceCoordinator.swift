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
        UIDevice.current.isBatteryMonitoringEnabled = true
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
    
    /// Check if heavy operations (extraction, cleanup, section detection, OCR) should proceed
    /// right now, per CLAUDE.md's "Pause AI processing when battery is low or device is hot".
    func shouldAllowHeavyOperations() -> Bool {
        if ProcessInfo.processInfo.thermalState == .critical || ProcessInfo.processInfo.thermalState == .serious {
            ReadForgeLogger.performanceWarning(operation: "Heavy Operation Gate", issue: "Thermal state is \(ProcessInfo.processInfo.thermalState)")
            return false
        }
        let device = UIDevice.current
        // batteryState == .unknown on Simulator / when monitoring isn't enabled — don't block
        // heavy work off an unreadable signal, only off a confirmed low, unplugged battery.
        if device.batteryState == .unplugged, device.batteryLevel >= 0, device.batteryLevel < 0.2 {
            ReadForgeLogger.performanceWarning(operation: "Heavy Operation Gate", issue: "Battery at \(Int(device.batteryLevel * 100))%, unplugged")
            return false
        }
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
        ) { _ in
            ReadForgeLogger.performanceWarning(operation: "Memory Warning", issue: "System reported low memory")
            // Previously logged only — on a genuine memory-pressure signal (e.g. mid-playback of
            // a large document with cached audio/text in memory), the app took no corrective
            // action at all, increasing the odds of an OS jetsam/OOM kill instead of gracefully
            // shedding cache the way this coordinator's own purpose implies it should.
            Task { await CacheManager.shared.performIntelligentCleanup() }
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
