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
