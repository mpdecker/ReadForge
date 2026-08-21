//
//  PerformanceBenchmarkTests.swift
//  ReadForgeTests
//
//  Created by Matthieu Decker on 5/10/26.
//

import Testing
import Foundation
import SwiftData
@testable import ReadForge

@Suite(.serialized)
@MainActor
struct PerformanceBenchmarkTests {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    
    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: DocumentRecord.self, SectionRecord.self, BookmarkRecord.self, PlaybackState.self, configurations: config)
        modelContext = modelContainer.mainContext
    }
    
    // MARK: - PDF Extraction Performance
    
    @Test
    func benchmarkPDFExtractionPerformance() async throws {
        let testURL = createLargeTestPDFFile()
        let extractionService = PDFExtractionService()
        
        let startTime = Date()
        let pages = try extractionService.extractPages(from: testURL)
        let duration = Date().timeIntervalSince(startTime)
        
        // Should extract pages within reasonable time (2 seconds for test file)
        #expect(duration < 2.0, "PDF extraction took too long: \(duration)s")
        #expect(!pages.isEmpty, "No pages extracted")
        
        // Performance logging
        ReadForgeLogger.performanceMetric(operation: "PDF Extraction Benchmark", duration: duration)
    }
    
    @Test
    func benchmarkTextCleanupPerformance() async throws {
        let cleanupService = TextCleanupService()

        let startTime = Date()
        let pages = (1...50).map { PageText(pageNumber: $0, text: "Line one on page \($0)\nBody text.\nFooter \($0)") }
        let cleanedText = cleanupService.clean(pages)
        let duration = Date().timeIntervalSince(startTime)
        
        // Should cleanup text within reasonable time (1 second for large text)
        #expect(duration < 1.0, "Text cleanup took too long: \(duration)s")
        #expect(!cleanedText.isEmpty, "Cleaned text is empty")
        
        ReadForgeLogger.performanceMetric(operation: "Text Cleanup Benchmark", duration: duration)
    }
    
    @Test
    func benchmarkSentenceChunkingPerformance() async throws {
        let chunker = SentenceChunker()
        let largeText = createLargeText()
        
        let startTime = Date()
        let chunks = chunker.chunk(largeText)
        let duration = Date().timeIntervalSince(startTime)
        
        // Should chunk text within reasonable time (0.5 seconds)
        #expect(duration < 0.5, "Sentence chunking took too long: \(duration)s")
        #expect(!chunks.isEmpty, "No chunks created")
        
        ReadForgeLogger.performanceMetric(operation: "Sentence Chunking Benchmark", duration: duration)
    }
    
    // MARK: - Memory Performance
    
    @Test(.disabled("MemoryManager not implemented in app target"))
    func benchmarkMemoryUsageDuringProcessing() async throws {}
    
    // MARK: - Storage Performance
    
    @Test(.disabled("StorageManager not implemented in app target"))
    func benchmarkStorageOperations() async throws {}
    
    @Test
    func benchmarkDatabaseOperations() async throws {
        let startTime = Date()
        
        // Create multiple documents
        for i in 1...10 {
            let document = DocumentRecord(title: "Test Document \(i)", fileURL: createTestPDFFile())
            modelContext.insert(document)
        }
        
        try modelContext.save()
        let saveDuration = Date().timeIntervalSince(startTime)
        
        // Should save 10 documents within reasonable time (1 second)
        #expect(saveDuration < 1.0, "Database save took too long: \(saveDuration)s")
        
        // Test fetch performance
        let fetchStartTime = Date()
        let fetchDescriptor = FetchDescriptor<DocumentRecord>()
        let documents = try modelContext.fetch(fetchDescriptor)
        let fetchDuration = Date().timeIntervalSince(fetchStartTime)
        
        #expect(documents.count == 10, "Wrong number of documents fetched")
        #expect(fetchDuration < 0.1, "Database fetch took too long: \(fetchDuration)s")
        
        ReadForgeLogger.performanceMetric(operation: "Database Save Benchmark", duration: saveDuration)
        ReadForgeLogger.performanceMetric(operation: "Database Fetch Benchmark", duration: fetchDuration)
    }
    
    // MARK: - Performance Coordinator Tests
    
    @Test
    func benchmarkPerformanceCoordinator() async throws {
        let coordinator = SimplePerformanceCoordinator()
        coordinator.startMonitoring()

        let startTime = Date()

        let document = createLargeTestDocument()
        let results = try await coordinator.processLargeDocument(document: document) { section in
            try await Task.sleep(nanoseconds: 10_000_000)
            return "Processed \(section.title)"
        }

        let duration = Date().timeIntervalSince(startTime)

        #expect(!results.isEmpty, "No processing results")
        #expect(duration < 2.0, "Performance coordinator processing took too long: \(duration)s")

        coordinator.stopMonitoring()

        ReadForgeLogger.performanceMetric(operation: "Performance Coordinator Benchmark", duration: duration)
    }
    
    // MARK: - Helper Methods
    
    private func createLargeTestPDFFile() -> URL {
        // The previous version wrote raw text between a PDF header and "%%EOF" with no real PDF
        // structure at all (no objects/xref/trailer) — PDFKit couldn't open it, so this
        // benchmark always failed with `.cannotOpen` rather than measuring anything.
        PDFTestFixtures.write(pageCount: 10, titlePrefix: "Performance Test Page", filename: "large_test_document.pdf")
    }

    private func createTestPDFFile() -> URL {
        // Same issue as above: the hand-rolled xref table had every object offset set to 0,
        // which PDFKit rejects outright.
        PDFTestFixtures.write(filename: "test_document.pdf")
    }
    
    private func createLargeDirtyText() -> String {
        var text = ""
        for i in 1...100 {
            text += """
            Chapter \(i): Test Chapter
            Page \(i) of 100
            This is some sample text that needs cleaning. It has headers and footers that should be removed.
            More content here with line breaks that should be joined properly.
            Page \(i + 1) of 100
            """
        }
        return text
    }
    
    private func createLargeText() -> String {
        var text = ""
        for i in 1...100 {
            text += "This is sentence \(i). This is another sentence for testing! How about a question? "
        }
        return text
    }
    
    private func createLargeTestDocument() -> DocumentRecord {
        let document = DocumentRecord(title: "Large Test Document", fileURL: createLargeTestPDFFile())
        
        // Add multiple sections
        for i in 1...20 {
            let section = SectionRecord(
                title: "Section \(i)",
                rawText: String(repeating: "Test content for section \(i). ", count: 50),
                order: i,
                startPage: i,
                endPage: i + 1
            )
            section.document = document
            document.sections.append(section)
        }
        
        return document
    }
}
