//
//  Logger.swift
//  ReadForge
//
//  Created by Matthieu Decker on 5/10/26.
//

import Foundation
import OSLog

/// Privacy-first structured logging for ReadForge
/// Never logs document content or user data
///
/// `nonisolated` (overriding this module's default MainActor isolation): every member here is a
/// stateless call into an `os.Logger` instance, which is `Sendable`/thread-safe by design — this
/// type has no actor affinity of its own. Without this, calling e.g. `ReadForgeLogger.error(...)`
/// from a `nonisolated` background context (PDF extraction, OCR, any other off-main service) is
/// a compile-time warning today ("call to main actor-isolated static method... in a synchronous
/// nonisolated context") and a real actor-isolation violation, not just style.
nonisolated enum ReadForgeLogger {
    private static let subsystem = "com.readforge.app"
    
    // MARK: - Log Categories
    private static let app = Logger(subsystem: subsystem, category: "App")
    private static let document = Logger(subsystem: subsystem, category: "Document")
    private static let playback = Logger(subsystem: subsystem, category: "Playback")
    private static let ai = Logger(subsystem: subsystem, category: "AI")
    private static let security = Logger(subsystem: subsystem, category: "Security")
    private static let performance = Logger(subsystem: subsystem, category: "Performance")
    
    // MARK: - App Lifecycle
    static func appDidLaunch() {
        app.info("Application launched")
    }
    
    static func appWillTerminate() {
        app.info("Application will terminate")
    }
    
    static func appDidEnterBackground() {
        app.info("Application entered background")
    }
    
    static func appWillEnterForeground() {
        app.info("Application will enter foreground")
    }
    
    // MARK: - Document Processing
    static func documentImportStarted(fileName: String) {
        document.info("Document import started: \(fileName, privacy: .public)")
    }
    
    static func documentImportCompleted(fileName: String, pageCount: Int) {
        document.info("Document import completed: \(fileName, privacy: .public), pages: \(pageCount)")
    }
    
    static func documentImportFailed(fileName: String, error: String) {
        document.error("Document import failed: \(fileName, privacy: .public), error: \(error, privacy: .public)")
    }
    
    static func documentExtractionStarted(documentId: String) {
        document.debug("Text extraction started: \(documentId, privacy: .private)")
    }
    
    static func documentExtractionCompleted(documentId: String, sectionsCount: Int, wordCount: Int) {
        document.info("Text extraction completed: \(documentId, privacy: .private), sections: \(sectionsCount), words: \(wordCount)")
    }
    
    static func documentExtractionFailed(documentId: String, error: String) {
        document.error("Text extraction failed: \(documentId, privacy: .private), error: \(error, privacy: .public)")
    }
    
    static func textCleanupStarted(documentId: String) {
        document.debug("Text cleanup started: \(documentId, privacy: .private)")
    }
    
    static func textCleanupCompleted(documentId: String, usedAI: Bool) {
        let method = usedAI ? "AI" : "deterministic"
        document.info("Text cleanup completed: \(documentId, privacy: .private), method: \(method)")
    }
    
    static func textCleanupFailed(documentId: String, error: String) {
        document.error("Text cleanup failed: \(documentId, privacy: .private), error: \(error, privacy: .public)")
    }
    
    // MARK: - Playback
    static func playbackStarted(documentId: String, sectionId: String) {
        playback.info("Playback started: document: \(documentId, privacy: .private), section: \(sectionId, privacy: .private)")
    }
    
    static func playbackPaused(documentId: String, sentenceIndex: Int) {
        playback.debug("Playback paused: document: \(documentId, privacy: .private), sentence: \(sentenceIndex)")
    }
    
    static func playbackStopped(documentId: String) {
        playback.info("Playback stopped: document: \(documentId, privacy: .private)")
    }
    
    static func playbackError(documentId: String, error: String) {
        playback.error("Playback error: document: \(documentId, privacy: .private), error: \(error, privacy: .public)")
    }
    
    static func progressSaved(documentId: String, sentenceIndex: Int) {
        playback.debug("Progress saved: document: \(documentId, privacy: .private), sentence: \(sentenceIndex)")
    }
    
    // MARK: - AI Model
    static func aiModelLoadStarted(modelName: String) {
        ai.info("AI model load started: \(modelName, privacy: .public)")
    }
    
    static func aiModelLoadCompleted(modelName: String) {
        ai.info("AI model load completed: \(modelName, privacy: .public)")
    }
    
    static func aiModelLoadFailed(modelName: String, error: String) {
        ai.error("AI model load failed: \(modelName, privacy: .public), error: \(error, privacy: .public)")
    }
    
    static func aiModelUnload(modelName: String) {
        ai.info("AI model unloaded: \(modelName, privacy: .public)")
    }
    
    static func aiInferenceStarted(documentId: String) {
        ai.debug("AI inference started: document: \(documentId, privacy: .private)")
    }
    
    static func aiInferenceCompleted(documentId: String, inputLength: Int, outputLength: Int) {
        ai.debug("AI inference completed: document: \(documentId, privacy: .private), input: \(inputLength) chars, output: \(outputLength) chars")
    }
    
    static func aiInferenceFailed(documentId: String, error: String) {
        ai.error("AI inference failed: document: \(documentId, privacy: .private), error: \(error, privacy: .public)")
    }
    
    // MARK: - Security
    static func securityFileAccessAttempted(filePath: String) {
        security.debug("File access attempted: \(filePath, privacy: .private)")
    }
    
    static func securityFileAccessGranted(filePath: String) {
        security.debug("File access granted: \(filePath, privacy: .private)")
    }
    
    static func securityFileAccessDenied(filePath: String) {
        security.warning("File access denied: \(filePath, privacy: .private)")
    }
    
    static func securityEncryptionOperation(operation: String, success: Bool) {
        if success {
            security.info("Encryption operation completed: \(operation, privacy: .public)")
        } else {
            security.error("Encryption operation failed: \(operation, privacy: .public)")
        }
    }
    
    static func securityValidationFailed(component: String, reason: String) {
        security.warning("Security validation failed: component: \(component, privacy: .public), reason: \(reason, privacy: .public)")
    }
    
    // MARK: - Performance
    static func performanceMetric(operation: String, duration: TimeInterval) {
        performance.info("Performance: \(operation, privacy: .public) completed in \(String(format: "%.2f", duration))s")
    }
    
    static func performanceMemoryUsage(component: String, memoryMB: Double) {
        performance.debug("Memory usage: \(component, privacy: .public) using \(String(format: "%.1f", memoryMB))MB")
    }
    
    static func performanceStorageUsage(operation: String, sizeMB: Double) {
        performance.debug("Storage usage: \(operation, privacy: .public) using \(String(format: "%.1f", sizeMB))MB")
    }
    
    static func performanceWarning(operation: String, issue: String) {
        performance.warning("Performance issue: \(operation, privacy: .public) - \(issue, privacy: .public)")
    }
    
    // MARK: - Error Handling
    static func error(category: String = "General", message: String, error: Error? = nil) {
        let errorMessage = error?.localizedDescription ?? "No error details"
        
        switch category.lowercased() {
        case "document":
            document.error("\(message): \(errorMessage, privacy: .public)")
        case "playback":
            playback.error("\(message): \(errorMessage, privacy: .public)")
        case "ai":
            ai.error("\(message): \(errorMessage, privacy: .public)")
        case "security":
            security.error("\(message): \(errorMessage, privacy: .public)")
        case "performance":
            performance.error("\(message): \(errorMessage, privacy: .public)")
        default:
            app.error("\(message): \(errorMessage, privacy: .public)")
        }
    }
    
    // MARK: - Debug
    static func debug(category: String = "General", message: String) {
        let logger: Logger
        
        switch category.lowercased() {
        case "document":
            logger = document
        case "playback":
            logger = playback
        case "ai":
            logger = ai
        case "security":
            logger = security
        case "performance":
            logger = performance
        default:
            logger = app
        }
        
        logger.debug("\(message, privacy: .public)")
    }
    
    // MARK: - Analytics (Privacy-Preserving)
    static func analyticsEvent(event: String, properties: [String: Any]? = nil) {
        var logMessage = "Analytics event: \(event)"
        
        if let properties = properties {
            let safeProperties = properties.filter { key, value in
                // Only log non-sensitive properties
                !key.contains("content") && 
                !key.contains("text") && 
                !key.contains("data") &&
                !key.contains("user") &&
                !(value is String && (value as! String).count > 100)
            }
            
            if !safeProperties.isEmpty {
                logMessage += " properties: \(safeProperties)"
            }
        }
        
        app.info("\(logMessage)")
    }
}

/// Performance measurement helper
struct PerformanceTimer {
    let operation: String
    let startTime: Date
    
    init(operation: String) {
        self.operation = operation
        self.startTime = Date()
    }
    
    func stop() {
        let duration = Date().timeIntervalSince(startTime)
        ReadForgeLogger.performanceMetric(operation: operation, duration: duration)
    }
}
