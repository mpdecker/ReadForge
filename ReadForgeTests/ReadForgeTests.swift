//
//  ReadForgeTests.swift
//  ReadForgeTests
//
//  Created by Matthieu Decker on 5/5/26.
//

import Foundation
import Testing
@testable import ReadForge

@MainActor
struct ReadForgeTests {
    
    @Test func testServiceContainerTypeSafety() async throws {
        let container = ServiceContainer.shared
        
        // Test that we can resolve services without crashes
        let importer = try await container.resolve(DocumentImportService.self)
        #expect(importer is DocumentImportService)
        
        let factory = try await container.resolve(DocumentExtractionFactory.self)
        #expect(factory is DocumentExtractionFactory)
    }
    
    // Regression test: `resolve(AIModelManaging.self)` (T bound to the protocol itself) used
    // to always fall through to `default` in `createDefaultInstance`'s switch and throw
    // `.serviceNotFound` — silently swallowed by `try?` at the LibraryViewModel call site, so
    // the Settings "Enhanced Cleanup" toggle had zero effect no matter what the user chose.
    // `aiCleanupService` now resolves via the concrete `TextCleanupAIService.self` instead.
    @Test func testAIModelManagingResolves() async throws {
        let container = ServiceContainer.shared
        let service = try await container.aiCleanupService
        #expect(service.isLoaded)
        let result = await service.runCleanup(on: "This is a perfectly ordinary sentence for testing purposes here.")
        #expect(result != nil)
    }

    @Test func testServiceContainerErrorHandling() async throws {
        let container = ServiceContainer.shared
        
        // Test that resolving non-existent service throws proper error
        do {
            _ = try await container.resolve(String.self)
            #expect(Bool(false), "Should have thrown error")
        } catch let error as ServiceContainerError {
            #expect(error.errorDescription?.contains("not registered") == true)
        }
    }
    
    @Test func testSecurityServiceValidation() {
        // Test file path validation
        #expect(SecurityService.validateFilePath("/safe/path.pdf") == true)
        #expect(SecurityService.validateFilePath("../../../etc/passwd") == false)
        #expect(SecurityService.validateFilePath("path\0with\0nulls") == false)
        // Real on-device sandbox/inbox paths live under /private/var/mobile/Containers/... —
        // a naive substring check for "/var" would reject every real import on a physical
        // device while appearing to work fine in Simulator (whose paths don't contain "/var").
        #expect(SecurityService.validateFilePath("/private/var/mobile/Containers/Data/Application/ABC-123/tmp/My Document.pdf") == true)
        // Traversal must still be caught even when embedded in an otherwise-normal path.
        #expect(SecurityService.validateFilePath("/private/var/mobile/Containers/Data/Application/ABC-123/../../etc/passwd") == false)
        // A path that directly targets a system directory (no ".." needed) should still be
        // rejected — checked as an absolute-path *prefix* this time, not the old substring
        // check, so it doesn't reintroduce the /var false-positive above.
        #expect(SecurityService.validateFilePath("/etc/passwd") == false)
        #expect(SecurityService.validateFilePath("/usr/bin/whoami") == false)
        // A path merely *containing* "etc" as part of a legitimate name must NOT be rejected —
        // confirms this is a prefix check, not the substring check that broke real imports.
        #expect(SecurityService.validateFilePath("/private/var/mobile/Containers/Data/Application/ABC-123/tmp/etcetera notes.pdf") == true)
    }
    
    @Test func testDocumentRecordWordCount() {
        let record = DocumentRecord(title: "Test", fileURL: URL(fileURLWithPath: "/tmp/test.pdf"))
        
        // Create a section with known word count
        let section = SectionRecord(
            title: "Test Section",
            rawText: "A B C D E F G",
            order: 1,
            startPage: 1,
            endPage: 1
        )
        section.document = record
        record.sections = [section]
        
        #expect(record.wordCount == 7)
        #expect(record.estimatedListeningMinutes > 0.0)
    }
    
    @Test func testSimpleAuthenticationService() {
        let authService = SimpleAuthenticationService()
        
        // Test initial state
        #expect(authService.isUnlocked == true) // Should be unlocked by default for local app
        
        // Test lock/unlock
        authService.lock()
        #expect(authService.isUnlocked == false)
        
        authService.unlock()
        #expect(authService.isUnlocked == true)
    }
}
