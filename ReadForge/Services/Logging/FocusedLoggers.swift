//
//  FocusedLoggers.swift
//  ReadForge
//
//  Created by Matthieu Decker on 5/10/26.
//

import Foundation
import OSLog

/// Focused logging categories for better organization and maintainability

// MARK: - App Logger

struct AppLogger {
    private static let logger = Logger(subsystem: "com.readforge.app", category: "App")
    
    static func didLaunch() {
        logger.info("Application launched")
    }
    
    static func willTerminate() {
        logger.info("Application will terminate")
    }
    
    static func didEnterBackground() {
        logger.info("Application entered background")
    }
    
    static func willEnterForeground() {
        logger.info("Application will enter foreground")
    }
    
    static func info(_ message: String) {
        logger.info("\(message)")
    }
    
    static func debug(_ message: String) {
        logger.debug("\(message)")
    }
    
    static func error(_ message: String, error: Error? = nil) {
        let errorMessage = error?.localizedDescription ?? "No error details"
        logger.error("\(message): \(errorMessage, privacy: .public)")
    }
}

// MARK: - Document Logger

struct DocumentLogger {
    private static let logger = Logger(subsystem: "com.readforge.app", category: "Document")
    
    static func importStarted(fileName: String) {
        logger.info("Document import started: \(fileName, privacy: .public)")
    }
    
    static func importCompleted(fileName: String, pageCount: Int) {
        logger.info("Document import completed: \(fileName, privacy: .public), pages: \(pageCount)")
    }
    
    static func importFailed(fileName: String, error: String) {
        logger.error("Document import failed: \(fileName, privacy: .public), error: \(error, privacy: .public)")
    }
    
    static func extractionStarted(documentId: String) {
        logger.debug("Text extraction started: \(documentId, privacy: .private)")
    }
    
    static func extractionCompleted(documentId: String, sectionsCount: Int, wordCount: Int) {
        logger.info("Text extraction completed: \(documentId, privacy: .private), sections: \(sectionsCount), words: \(wordCount)")
    }
    
    static func extractionFailed(documentId: String, error: String) {
        logger.error("Text extraction failed: \(documentId, privacy: .private), error: \(error, privacy: .public)")
    }
    
    static func cleanupStarted(documentId: String) {
        logger.debug("Text cleanup started: \(documentId, privacy: .private)")
    }
    
    static func cleanupCompleted(documentId: String, usedAI: Bool) {
        let method = usedAI ? "AI" : "deterministic"
        logger.info("Text cleanup completed: \(documentId, privacy: .private), method: \(method)")
    }
    
    static func cleanupFailed(documentId: String, error: String) {
        logger.error("Text cleanup failed: \(documentId, privacy: .private), error: \(error, privacy: .public)")
    }
}

// MARK: - Playback Logger

struct PlaybackLogger {
    private static let logger = Logger(subsystem: "com.readforge.app", category: "Playback")
    
    static func started(documentId: String, sectionId: String) {
        logger.info("Playback started: document: \(documentId, privacy: .private), section: \(sectionId, privacy: .private)")
    }
    
    static func paused(documentId: String, sentenceIndex: Int) {
        logger.debug("Playback paused: document: \(documentId, privacy: .private), sentence: \(sentenceIndex)")
    }
    
    static func stopped(documentId: String) {
        logger.info("Playback stopped: document: \(documentId, privacy: .private)")
    }
    
    static func error(documentId: String, error: String) {
        logger.error("Playback error: document: \(documentId, privacy: .private), error: \(error, privacy: .public)")
    }
    
    static func progressSaved(documentId: String, sentenceIndex: Int) {
        logger.debug("Progress saved: document: \(documentId, privacy: .private), sentence: \(sentenceIndex)")
    }
    
    static func info(_ message: String) {
        logger.info("\(message)")
    }
    
    static func debug(_ message: String) {
        logger.debug("\(message)")
    }
}

// MARK: - AI Logger

struct AILogger {
    private static let logger = Logger(subsystem: "com.readforge.app", category: "AI")
    
    static func modelLoadStarted(modelName: String) {
        logger.info("AI model load started: \(modelName, privacy: .public)")
    }
    
    static func modelLoadCompleted(modelName: String) {
        logger.info("AI model load completed: \(modelName, privacy: .public)")
    }
    
    static func modelLoadFailed(modelName: String, error: String) {
        logger.error("AI model load failed: \(modelName, privacy: .public), error: \(error, privacy: .public)")
    }
    
    static func modelUnload(modelName: String) {
        logger.info("AI model unloaded: \(modelName, privacy: .public)")
    }
    
    static func inferenceStarted(documentId: String) {
        logger.debug("AI inference started: document: \(documentId, privacy: .private)")
    }
    
    static func inferenceCompleted(documentId: String, inputLength: Int, outputLength: Int) {
        logger.debug("AI inference completed: document: \(documentId, privacy: .private), input: \(inputLength) chars, output: \(outputLength) chars")
    }
    
    static func inferenceFailed(documentId: String, error: String) {
        logger.error("AI inference failed: document: \(documentId, privacy: .private), error: \(error, privacy: .public)")
    }
}

// MARK: - Security Logger

struct SecurityLogger {
    private static let logger = Logger(subsystem: "com.readforge.app", category: "Security")
    
    static func fileAccessAttempted(filePath: String) {
        logger.debug("File access attempted: \(filePath, privacy: .private)")
    }
    
    static func fileAccessGranted(filePath: String) {
        logger.debug("File access granted: \(filePath, privacy: .private)")
    }
    
    static func fileAccessDenied(filePath: String) {
        logger.warning("File access denied: \(filePath, privacy: .private)")
    }
    
    static func encryptionOperation(operation: String, success: Bool) {
        if success {
            logger.info("Encryption operation completed: \(operation, privacy: .public)")
        } else {
            logger.error("Encryption operation failed: \(operation, privacy: .public)")
        }
    }
    
    static func validationFailed(component: String, reason: String) {
        logger.warning("Security validation failed: component: \(component, privacy: .public), reason: \(reason, privacy: .public)")
    }
}

// MARK: - Performance Logger

struct PerformanceLogger {
    private static let logger = Logger(subsystem: "com.readforge.app", category: "Performance")
    
    static func metric(operation: String, duration: TimeInterval) {
        logger.info("Performance: \(operation, privacy: .public) completed in \(String(format: "%.2f", duration))s")
    }
    
    static func memoryUsage(component: String, memoryMB: Double) {
        logger.debug("Memory usage: \(component, privacy: .public) using \(String(format: "%.1f", memoryMB))MB")
    }
    
    static func storageUsage(operation: String, sizeMB: Double) {
        logger.debug("Storage usage: \(operation, privacy: .public) using \(String(format: "%.1f", sizeMB))MB")
    }
    
    static func warning(operation: String, issue: String) {
        logger.warning("Performance issue: \(operation, privacy: .public) - \(issue, privacy: .public)")
    }
    
    static func debug(_ message: String) {
        logger.debug("\(message)")
    }
}

// MARK: - Analytics Logger

struct AnalyticsLogger {
    private static let logger = Logger(subsystem: "com.readforge.app", category: "Analytics")
    
    static func event(event: String, properties: [String: Any]? = nil) {
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
        
        logger.info("\(logMessage)")
    }
}

// MARK: - Cache Logger

struct CacheLogger {
    private static let logger = Logger(subsystem: "com.readforge.app", category: "Cache")
    
    static func info(_ message: String) {
        logger.info("\(message)")
    }
    
    static func debug(_ message: String) {
        logger.debug("\(message)")
    }
    
    static func error(_ message: String, error: Error? = nil) {
        let errorMessage = error?.localizedDescription ?? "No error details"
        logger.error("\(message): \(errorMessage, privacy: .public)")
    }
}

// MARK: - Battery Logger

struct BatteryLogger {
    private static let logger = Logger(subsystem: "com.readforge.app", category: "Battery")
    
    static func levelChanged(level: Float, mode: String) {
        logger.debug("Battery level: \(Int(level * 100))%, Mode: \(mode)")
    }
    
    static func warning(operation: String, issue: String) {
        logger.warning("Battery issue: \(operation, privacy: .public) - \(issue, privacy: .public)")
    }
}

// MARK: - Thermal Logger

struct ThermalLogger {
    private static let logger = Logger(subsystem: "com.readforge.app", category: "Thermal")
    
    static func stateChanged(state: String) {
        logger.debug("Thermal state: \(state)")
    }
    
    static func warning(operation: String, issue: String) {
        logger.warning("Thermal issue: \(operation, privacy: .public) - \(issue, privacy: .public)")
    }
}

// MARK: - Storage Logger

struct StorageLogger {
    static func info(_ message: String) {
        ReadForgeLogger.debug(category: "Storage", message: message)
    }
    
    static func error(_ message: String, error: Error) {
        ReadForgeLogger.error(category: "Storage", message: message, error: error)
    }
    
    static func debug(_ message: String) {
        ReadForgeLogger.debug(category: "Storage", message: message)
    }
}

// MARK: - Security Logger

struct SecurityLoggerV2 {
    static func info(_ message: String) {
        ReadForgeLogger.securityValidationFailed(component: "Authentication", reason: message)
    }
    
    static func error(_ message: String, error: Error) {
        ReadForgeLogger.error(category: "Security", message: message, error: error)
    }
    
    static func debug(_ message: String) {
        ReadForgeLogger.debug(category: "Security", message: message)
    }
    
    // `email` is intentionally not included in the logged reason — `securityValidationFailed`
    // logs its `reason` string at `.public` privacy (see `Logger.swift`), unlike every other
    // user-identifying value logged elsewhere in this app (documentId, filePath), which is
    // always `.private`. Splicing the raw address into a public-privacy string would have
    // written it unredacted to the unified logging system, visible via Console.app/sysdiagnose
    // with no special entitlement — directly contradicting this file's own "never logs document
    // content or user data" contract. Matches `biometricAttempt` below, which already logs no
    // identifying info for the same reason.
    static func authenticationAttempt(email: String, success: Bool) {
        if success {
            ReadForgeLogger.securityValidationFailed(component: "Authentication", reason: "Successful login")
        } else {
            ReadForgeLogger.securityValidationFailed(component: "Authentication", reason: "Failed login attempt")
        }
    }
    
    static func biometricAttempt(success: Bool) {
        if success {
            ReadForgeLogger.securityValidationFailed(component: "Biometrics", reason: "Successful biometric authentication")
        } else {
            ReadForgeLogger.securityValidationFailed(component: "Biometrics", reason: "Failed biometric authentication")
        }
    }
    
    static func tokenOperation(operation: String, success: Bool) {
        ReadForgeLogger.securityEncryptionOperation(operation: operation, success: success)
    }
}
