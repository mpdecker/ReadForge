//
//  ServiceContainer.swift
//  ReadForge
//
//  Created by Matthieu Decker on 5/10/26.
//

import Foundation
import SwiftData

/// Type-safe dependency injection container for managing service instances
/// Uses generic types instead of strings for compile-time safety
actor ServiceContainer {
    
    // MARK: - Singleton
    static let shared = ServiceContainer()
    
    private init() {}
    
    // MARK: - Service Registry
    
    private var services: [ObjectIdentifier: Any] = [:]
    private var factories: [ObjectIdentifier: () -> Any] = [:]
    
    // MARK: - Registration Methods
    
    /// Register a service instance
    func register<T>(_ type: T.Type, instance: T) {
        let key = ObjectIdentifier(type)
        services[key] = instance
    }
    
    /// Register a service factory
    func register<T>(_ type: T.Type, factory: @escaping () -> T) {
        let key = ObjectIdentifier(type)
        factories[key] = factory
    }
    
    /// Register a service factory with dependencies
    func register<T>(_ type: T.Type, factory: @escaping (ServiceContainer) -> T) {
        let key = ObjectIdentifier(type)
        factories[key] = { factory(Self.shared) }
    }
    
    // MARK: - Resolution Methods
    
    /// Resolve a service instance
    func resolve<T>(_ type: T.Type) async throws -> T {
        let key = ObjectIdentifier(type)
        
        // Check for existing instance
        if let instance = services[key] as? T {
            return instance
        }
        
        // Check for factory
        if let factory = factories[key] {
            guard let instance = factory() as? T else {
                throw ServiceContainerError.serviceCreationFailed(String(describing: type))
            }
            services[key] = instance
            return instance
        }
        
        // Try to create default instance
        if let defaultInstance = await createDefaultInstance(for: type) {
            services[key] = defaultInstance
            return defaultInstance
        }
        
        throw ServiceContainerError.serviceNotFound(String(describing: type))
    }
    
    /// Resolve an optional service instance
    func resolveOptional<T>(_ type: T.Type) async -> T? {
        do {
            return try await resolve(type)
        } catch {
            return nil
        }
    }
    
    // MARK: - Default Instance Creation
    
    private func createDefaultInstance<T>(for type: T.Type) async -> T? {
        switch type {
        case is DocumentImportService.Type:
            return DocumentImportService() as? T
        case is DocumentExtractionFactory.Type:
            return DocumentExtractionFactory() as? T
        case is TextCleanupService.Type:
            return TextCleanupService() as? T
        case is PDFSectionDetectionService.Type:
            return PDFSectionDetectionService() as? T
        case is PDFExtractionService.Type:
            return PDFExtractionService() as? T
        case is EPUBExtractionService.Type:
            return EPUBExtractionService() as? T
        case is PlainTextExtractionService.Type:
            return PlainTextExtractionService() as? T
        case is TieredTextCleanupService.Type:
            return TieredTextCleanupService() as? T
        case is OCRService.Type:
            return OCRService() as? T
        case is PlaybackController.Type:
            return await MainActor.run { PlaybackController() as? T }
        case is SimplePerformanceCoordinator.Type:
            return await MainActor.run { SimplePerformanceCoordinator() as? T }
        default:
            return nil
        }
    }
    
    // MARK: - Lifecycle
    
    /// Clear all services (for testing)
    func clear() {
        services.removeAll()
        factories.removeAll()
    }
    
    /// Remove a specific service
    func remove<T>(_ type: T.Type) {
        let key = ObjectIdentifier(type)
        services.removeValue(forKey: key)
        factories.removeValue(forKey: key)
    }
}

// MARK: - Error Types

enum ServiceContainerError: LocalizedError {
    case serviceNotFound(String)
    case serviceCreationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .serviceNotFound(let typeName):
            return "Service of type '\(typeName)' not registered and no default instance available"
        case .serviceCreationFailed(let typeName):
            return "Failed to create service of type '\(typeName)'"
        }
    }
}

// MARK: - Convenience Extensions

extension ServiceContainer {
    
    /// Convenience property for common services
    var documentImportService: DocumentImportService {
        get async throws { try await resolve(DocumentImportService.self) }
    }
    
    var extractionFactory: DocumentExtractionFactory {
        get async throws { try await resolve(DocumentExtractionFactory.self) }
    }
    
    var textCleanupService: TextCleanupService {
        get async throws { try await resolve(TextCleanupService.self) }
    }
    
    // Resolved by the CONCRETE type (`PDFSectionDetectionService`), not the `SectionDetectionService`
    // protocol — same `switch type { case is ProtocolType.Type }` gotcha documented below on
    // `aiCleanupService` (never matches when `T` is bound to the protocol itself). This one was
    // missed when that fix was applied elsewhere: `resolve(SectionDetectionService.self)` always
    // threw `.serviceNotFound`, and `LibraryViewModel.importAndProcess` calls this getter with
    // `try await` (not `try?`), so the `do` block's `catch` fired immediately on every single
    // import — every PDF/EPUB/text import failed before any file was even touched.
    var sectionDetectionService: SectionDetectionService {
        get async throws { try await resolve(PDFSectionDetectionService.self) }
    }

    // Resolved by the CONCRETE type (`TieredTextCleanupService`), not the `AIModelManaging`
    // protocol — `switch type { case is AIModelManaging.Type: ... }` inside
    // `createDefaultInstance<T>` never matches when `T` is bound to the protocol itself
    // (confirmed: Swift's `is` pattern match on a generic `T.Type` value doesn't satisfy a
    // protocol-metatype case the way it does for a concrete type). That silently made every
    // call here throw `.serviceNotFound`, swallowed by the `try?` at the call site, so the
    // "Enhanced Cleanup" toggle in Settings had zero effect no matter what the user chose.
    //
    // `TieredTextCleanupService` itself prefers Apple's on-device Foundation Model (a real
    // generative LLM, iOS 26+ on eligible hardware) and falls back to `TextCleanupAIService`'s
    // NaturalLanguage-based pass everywhere else — see that type's doc comment.
    var aiCleanupService: AIModelManaging {
        get async throws { try await resolve(TieredTextCleanupService.self) }
    }

    var ocrService: OCRService {
        get async throws { try await resolve(OCRService.self) }
    }

    var performanceCoordinator: SimplePerformanceCoordinator {
        get async throws { try await resolve(SimplePerformanceCoordinator.self) }
    }
}
