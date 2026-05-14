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
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("large_test_document.pdf")
        
        // Create a larger PDF for performance testing
        let largePDFData = createLargePDFData()
        try! largePDFData.write(to: testFile)
        return testFile
    }
    
    private func createTestPDFFile() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test_document.pdf")
        
        let minimalPDF = Data([
            0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34, 0x0A, 0x25, 0xC3, 0xA9, 0xC3, 0xB1, 0xC3, 0xB3,
            0x0A, 0x31, 0x20, 0x30, 0x20, 0x6F, 0x62, 0x6A, 0x0A, 0x3C, 0x3C, 0x2F, 0x54, 0x69, 0x74, 0x6C,
            0x65, 0x20, 0x28, 0x54, 0x65, 0x73, 0x74, 0x20, 0x44, 0x6F, 0x63, 0x75, 0x6D, 0x65, 0x6E, 0x74,
            0x29, 0x2F, 0x43, 0x72, 0x65, 0x61, 0x74, 0x6F, 0x72, 0x20, 0x28, 0x54, 0x65, 0x73, 0x74, 0x29, 0x2F,
            0x50, 0x72, 0x6F, 0x64, 0x75, 0x63, 0x65, 0x72, 0x20, 0x28, 0x54, 0x65, 0x73, 0x74, 0x29, 0x3E, 0x3E,
            0x0A, 0x65, 0x6E, 0x64, 0x6F, 0x62, 0x6A, 0x0A, 0x32, 0x20, 0x30, 0x20, 0x6F, 0x62, 0x6A, 0x0A, 0x3C,
            0x3C, 0x2F, 0x54, 0x79, 0x70, 0x65, 0x20, 0x2F, 0x43, 0x61, 0x74, 0x61, 0x6C, 0x6F, 0x67, 0x2F, 0x50,
            0x61, 0x67, 0x65, 0x73, 0x20, 0x32, 0x20, 0x30, 0x20, 0x52, 0x3E, 0x3E, 0x0A, 0x65, 0x6E, 0x64, 0x6F,
            0x62, 0x6A, 0x0A, 0x33, 0x20, 0x30, 0x20, 0x6F, 0x62, 0x6A, 0x0A, 0x3C, 0x3C, 0x2F, 0x54, 0x79, 0x70,
            0x65, 0x20, 0x2F, 0x50, 0x61, 0x67, 0x65, 0x73, 0x2F, 0x4B, 0x69, 0x64, 0x73, 0x5B, 0x34, 0x20, 0x30,
            0x20, 0x52, 0x5D, 0x2F, 0x43, 0x6F, 0x75, 0x6E, 0x74, 0x20, 0x31, 0x3E, 0x3E, 0x0A, 0x65, 0x6E, 0x64, 0x6F,
            0x62, 0x6A, 0x0A, 0x34, 0x20, 0x30, 0x20, 0x6F, 0x62, 0x6A, 0x0A, 0x3C, 0x3C, 0x2F, 0x54, 0x79, 0x70, 0x65,
            0x20, 0x2F, 0x50, 0x61, 0x67, 0x65, 0x2F, 0x50, 0x61, 0x72, 0x65, 0x6E, 0x74, 0x20, 0x32, 0x20, 0x30, 0x20,
            0x52, 0x2F, 0x52, 0x65, 0x73, 0x6F, 0x75, 0x72, 0x63, 0x65, 0x73, 0x3C, 0x3C, 0x2F, 0x46, 0x6F, 0x6E, 0x74,
            0x3C, 0x3C, 0x2F, 0x46, 0x31, 0x20, 0x35, 0x20, 0x30, 0x20, 0x52, 0x3E, 0x3E, 0x3E, 0x2F, 0x4D, 0x65, 0x64,
            0x69, 0x61, 0x42, 0x6F, 0x78, 0x5B, 0x30, 0x20, 0x30, 0x20, 0x36, 0x31, 0x32, 0x20, 0x37, 0x39, 0x32, 0x5D,
            0x2F, 0x43, 0x6F, 0x6E, 0x74, 0x65, 0x6E, 0x74, 0x73, 0x20, 0x36, 0x20, 0x30, 0x20, 0x52, 0x3E, 0x3E, 0x0A,
            0x65, 0x6E, 0x64, 0x6F, 0x62, 0x6A, 0x0A, 0x35, 0x20, 0x30, 0x20, 0x6F, 0x62, 0x6A, 0x0A, 0x3C, 0x3C, 0x2F, 0x54,
            0x79, 0x70, 0x65, 0x20, 0x2F, 0x46, 0x6F, 0x6E, 0x74, 0x2F, 0x53, 0x75, 0x62, 0x74, 0x79, 0x70, 0x65, 0x20, 0x2F,
            0x54, 0x79, 0x70, 0x65, 0x31, 0x2F, 0x42, 0x61, 0x73, 0x65, 0x46, 0x6F, 0x6E, 0x74, 0x20, 0x2F, 0x48, 0x65, 0x6C,
            0x76, 0x65, 0x74, 0x69, 0x63, 0x61, 0x3E, 0x3E, 0x0A, 0x65, 0x6E, 0x64, 0x6F, 0x62, 0x6A, 0x0A, 0x36, 0x20, 0x30,
            0x20, 0x6F, 0x62, 0x6A, 0x0A, 0x3C, 0x3C, 0x2F, 0x4C, 0x65, 0x6E, 0x67, 0x74, 0x68, 0x20, 0x34, 0x34, 0x3E, 0x3E,
            0x0A, 0x73, 0x74, 0x72, 0x65, 0x61, 0x6D, 0x0A, 0x42, 0x54, 0x0A, 0x2F, 0x46, 0x31, 0x20, 0x31, 0x32, 0x20, 0x54,
            0x66, 0x0A, 0x37, 0x32, 0x20, 0x37, 0x30, 0x32, 0x20, 0x54, 0x64, 0x0A, 0x28, 0x54, 0x65, 0x73, 0x74, 0x20, 0x63,
            0x6F, 0x6E, 0x74, 0x65, 0x6E, 0x74, 0x29, 0x20, 0x54, 0x6A, 0x0A, 0x45, 0x54, 0x0A, 0x65, 0x6E, 0x64, 0x73, 0x74,
            0x72, 0x65, 0x61, 0x6D, 0x0A, 0x65, 0x6E, 0x64, 0x6F, 0x62, 0x6A, 0x0A, 0x78, 0x72, 0x65, 0x66, 0x0A, 0x30, 0x20,
            0x36, 0x0A, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x20, 0x36, 0x35, 0x35, 0x33,
            0x35, 0x20, 0x66, 0x0A, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x20, 0x30, 0x30, 0x30,
            0x30, 0x30, 0x6E, 0x0A, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x20, 0x30, 0x30, 0x30,
            0x30, 0x30, 0x6E, 0x0A, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x20, 0x30, 0x30, 0x30,
            0x30, 0x30, 0x6E, 0x0A, 0x74, 0x72, 0x61, 0x69, 0x6C, 0x65, 0x72, 0x0A, 0x3C, 0x3C, 0x2F, 0x53, 0x69, 0x7A, 0x65,
            0x20, 0x36, 0x2F, 0x52, 0x6F, 0x6F, 0x74, 0x20, 0x31, 0x20, 0x30, 0x20, 0x52, 0x3E, 0x3E, 0x0A, 0x73, 0x74, 0x61, 0x72,
            0x74, 0x78, 0x72, 0x65, 0x66, 0x0A, 0x35, 0x30, 0x30, 0x0A, 0x25, 0x25, 0x45, 0x4F, 0x46
        ])
        
        try! minimalPDF.write(to: testFile)
        return testFile
    }
    
    private func createLargePDFData() -> Data {
        // For performance testing, create a larger PDF
        // This is a simplified version - in real implementation would create proper multi-page PDF
        var data = Data()
        
        // PDF header
        data.append(contentsOf: [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34, 0x0A])
        
        // Add multiple pages content
        for i in 1...10 {
            let pageContent = "This is page \(i) with some test content for performance testing. " +
                           String(repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", count: 20)
            
            if let contentData = pageContent.data(using: .utf8) {
                data.append(contentData)
                data.append(contentsOf: [0x0A])
            }
        }
        
        // PDF footer
        data.append(contentsOf: [0x25, 0x25, 0x45, 0x4F, 0x46])
        
        return data
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
