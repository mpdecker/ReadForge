//
//  DocumentProcessingIntegrationTests.swift
//  ReadForgeTests
//

import Foundation
import SwiftData
import Testing
@testable import ReadForge

@Suite(.serialized)
@MainActor
struct DocumentProcessingIntegrationTests {

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(
            for: DocumentRecord.self, SectionRecord.self, BookmarkRecord.self, PlaybackState.self,
            configurations: config
        )
        modelContext = modelContainer.mainContext
    }

    @Test
    func testDocumentImportToProcessingPipeline() async throws {
        let testURL = createTestPDFFile()
        let importService = DocumentImportService()

        let document = try importService.importDocument(from: testURL)
        modelContext.insert(document)
        try modelContext.save()

        #expect(document.title == "test_document")
        #expect(document.processingStatus == .imported)
        #expect(document.sections.isEmpty)
    }

    @Test
    func testPDFExtractionService() async throws {
        let testURL = createTestPDFFile()
        let extractionService = PDFExtractionService()

        let pages = try extractionService.extractPages(from: testURL)

        #expect(!pages.isEmpty)
        #expect(pages.allSatisfy { !$0.text.isEmpty })
    }

    @Test
    func testTextCleanupService() async throws {
        // The header/footer stripper only removes lines that are actually *repeated* across
        // multiple pages (per CLAUDE.md's "remove any line repeated on 30%+ of pages" rule) —
        // a single page with one-off "Page X of Y" text has nothing to compare against, so it
        // can never qualify. Use several pages that genuinely repeat a header/footer instead.
        let cleanupService = TextCleanupService()

        let pages = (1...5).map { i in
            PageText(
                pageNumber: i,
                text: """
                Confidential — Do Not Distribute
                This is some sample text that needs cleaning on page \(i).
                It has headers and footers that should be removed.
                More content unique to page \(i), joined properly.
                Confidential — Do Not Distribute
                """
            )
        }
        let cleanedText = cleanupService.clean(pages)

        // "Confidential — Do Not Distribute" is identical on every page, so it's a genuine
        // repeated header/footer. Per-page text like "on page 1" is NOT repeated (each page
        // says something different) and must be left alone.
        #expect(!cleanedText.contains("Confidential"))
        #expect(cleanedText.contains("sample text"))
        #expect(cleanedText.contains("More content"))
    }

    @Test
    func testSentenceChunker() async throws {
        // A 300–800 char target chunk means a handful of short sentences legitimately merge
        // into a single chunk (below `minLength`) rather than splitting — that's correct
        // behavior per CLAUDE.md's utterance sizing, not a bug. Use enough sentences that a
        // split is actually expected.
        let chunker = SentenceChunker()
        // ~95 chars/repeat; need to clear the 800-char maxLength by a comfortable margin to
        // guarantee at least one split regardless of exact merge-boundary rounding.
        let longText = Array(
            repeating: "This is sentence one. This is sentence two! This is sentence three? And this is sentence four.",
            count: 15
        ).joined(separator: " ")

        let chunks = chunker.chunk(longText)

        #expect(chunks.count >= 2)
        #expect(chunks.allSatisfy { !$0.isEmpty })
        #expect(chunks.joined().contains("sentence one"))
        #expect(chunks.joined().contains("sentence four"))
    }

    @Test
    func testPlaybackProgressSaving() async throws {
        let document = DocumentRecord(title: "Test Document", fileURL: createTestPDFFile())
        let section = SectionRecord(
            title: "Test Section",
            rawText: "Test content",
            order: 1,
            startPage: 1,
            endPage: 1
        )
        section.document = document
        section.cleanText = "Clean content"

        modelContext.insert(document)
        modelContext.insert(section)
        try modelContext.save()

        StorageService.updateProgress(
            document: document,
            sectionId: section.id,
            sentenceIndex: 5,
            characterOffset: 100,
            context: modelContext
        )

        let fetchedDocument = try StorageService.fetchDocument(id: document.id, context: modelContext)
        #expect(fetchedDocument?.playbackState?.sentenceIndex == 5)
        #expect(fetchedDocument?.playbackState?.characterOffset == 100)
    }

    @Test
    func testDocumentFormatDetection() async throws {
        let pdfURL = createTestPDFFile()
        #expect(DocumentFormat(url: pdfURL) == .pdf)

        let epubURL = createTestEPUBFile()
        #expect(DocumentFormat(url: epubURL) == .epub)

        let textURL = createTestTextFile()
        #expect(DocumentFormat(url: textURL) == .txt)

        let unsupportedURL = URL(fileURLWithPath: "/test/image.jpg")
        #expect(DocumentFormat(url: unsupportedURL) == nil)
    }

    @Test
    func testErrorHandlingInImportService() async throws {
        let importService = DocumentImportService()

        let nonExistentURL = URL(fileURLWithPath: "/nonexistent/file.pdf")
        await #expect(throws: ImportError.self) {
            try importService.importDocument(from: nonExistentURL)
        }

        let unsupportedURL = createTestUnsupportedFile()
        await #expect(throws: ImportError.self) {
            try importService.importDocument(from: unsupportedURL)
        }
    }

    // MARK: - Helpers

    private func createTestPDFFile() -> URL {
        // The previous hand-rolled PDF byte array had an invalid xref table (every object
        // offset was 0), so PDFKit couldn't open it at all — every test using it failed with
        // `.cannotOpen`. Rendering via PDFTestFixtures produces a real, valid PDF instead.
        PDFTestFixtures.write(filename: "test_document.pdf")
    }

    private func createTestEPUBFile() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test.epub")
        let testData = "PK\u{03}\u{04}test epub content"
        try! testData.write(to: testFile, atomically: true, encoding: .utf8)
        return testFile
    }

    private func createTestTextFile() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test.txt")
        try! "Test text content".write(to: testFile, atomically: true, encoding: .utf8)
        return testFile
    }

    private func createTestUnsupportedFile() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test.jpg")
        try! Data([0xFF, 0xD8, 0xFF, 0xE0]).write(to: testFile)
        return testFile
    }
}
