import Testing
import Foundation
import SwiftData
@testable import ReadForge

@Suite(.serialized)
@MainActor
struct BackupServiceTests {
    var sourceContainer: ModelContainer!
    var sourceContext: ModelContext!
    var destContainer: ModelContainer!
    var destContext: ModelContext!

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        sourceContainer = try ModelContainer(
            for: DocumentRecord.self, SectionRecord.self, BookmarkRecord.self, PlaybackState.self,
            configurations: config
        )
        sourceContext = sourceContainer.mainContext

        destContainer = try ModelContainer(
            for: DocumentRecord.self, SectionRecord.self, BookmarkRecord.self, PlaybackState.self,
            configurations: config
        )
        destContext = destContainer.mainContext
    }

    // Also exercises the memory-shape fix: export/import now process one document's snapshot
    // at a time (see BackupService's Manifest.documentIds + Documents/<id>.json layout) instead
    // of holding every document's raw+clean section text in one array — this confirms the
    // round trip still preserves everything correctly under that new layout.
    @Test func exportThenImportRoundTripsDocumentSectionsBookmarksAndProgress() async throws {
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("Hello, this is a test document.".utf8).write(to: tmpFile)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let document = DocumentRecord(title: "Test Book", fileURL: tmpFile, author: "Test Author")
        document.processingStatus = .ready
        sourceContext.insert(document)

        let section = SectionRecord(title: "Chapter 1", rawText: "Raw chapter text.", order: 0, startPage: 1, endPage: 5)
        section.cleanText = "Clean chapter text."
        section.document = document
        sourceContext.insert(section)
        document.sections = [section]

        let bookmark = BookmarkRecord(sectionId: section.id, sentenceIndex: 3, note: "Interesting bit")
        bookmark.document = document
        sourceContext.insert(bookmark)
        document.bookmarks = [bookmark]

        let playbackState = PlaybackState(documentId: document.id, sectionId: section.id, sentenceIndex: 2, characterOffset: 10)
        document.playbackState = playbackState
        sourceContext.insert(playbackState)

        try sourceContext.save()

        let backupURL = try await BackupService().exportBackup(context: sourceContext)
        defer { try? FileManager.default.removeItem(at: backupURL) }

        // Restore into a completely separate, empty context — simulating a different device.
        try await BackupService().importBackup(from: backupURL, context: destContext)

        let restoredDocuments = try destContext.fetch(FetchDescriptor<DocumentRecord>())
        #expect(restoredDocuments.count == 1)
        let restored = try #require(restoredDocuments.first)
        #expect(restored.id == document.id)
        #expect(restored.title == "Test Book")
        #expect(restored.author == "Test Author")
        #expect(restored.sections.count == 1)
        #expect(restored.sections.first?.id == section.id)
        #expect(restored.sections.first?.rawText == "Raw chapter text.")
        #expect(restored.sections.first?.cleanText == "Clean chapter text.")
        #expect(restored.bookmarks.count == 1)
        #expect(restored.bookmarks.first?.note == "Interesting bit")
        #expect(restored.playbackState?.sentenceIndex == 2)
        #expect(restored.playbackState?.characterOffset == 10)
    }

    // Written as manual do/catch rather than `#expect(throws:)` — a `ModelContext` captured
    // directly inside a `#expect(throws:)` closure crashes this toolchain (Swift Testing +
    // SwiftData interaction, EXC_BREAKPOINT/SIGTRAP), confirmed via a from-scratch minimal
    // repro outside this file. It doesn't crash when the context is only ever accessed through
    // a wrapping class (e.g. `AuthenticationService`) rather than captured as a bare local —
    // see this project's other `#expect(throws:)` uses in AuthenticationTests, which are fine.
    @Test func exportWithNoDocumentsThrows() async throws {
        do {
            _ = try await BackupService().exportBackup(context: sourceContext)
            Issue.record("Expected BackupError.noDocuments to be thrown")
        } catch let error as BackupService.BackupError {
            #expect(error == .noDocuments)
        }
    }

    @Test func importingTheSameBackupTwiceDoesNotDuplicate() async throws {
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("Content.".utf8).write(to: tmpFile)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let document = DocumentRecord(title: "Once Only", fileURL: tmpFile)
        sourceContext.insert(document)
        try sourceContext.save()

        let backupURL = try await BackupService().exportBackup(context: sourceContext)
        defer { try? FileManager.default.removeItem(at: backupURL) }

        try await BackupService().importBackup(from: backupURL, context: destContext)
        try await BackupService().importBackup(from: backupURL, context: destContext)

        let documents = try destContext.fetch(FetchDescriptor<DocumentRecord>())
        #expect(documents.count == 1, "Restoring the same backup twice shouldn't create duplicates")
    }

    @Test func multipleDocumentsAllSurviveTheRoundTrip() async throws {
        var tmpFiles: [URL] = []
        defer { for f in tmpFiles { try? FileManager.default.removeItem(at: f) } }

        for i in 0..<3 {
            let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
            try Data("Document \(i) content.".utf8).write(to: tmpFile)
            tmpFiles.append(tmpFile)

            let document = DocumentRecord(title: "Doc \(i)", fileURL: tmpFile)
            sourceContext.insert(document)
        }
        try sourceContext.save()

        let backupURL = try await BackupService().exportBackup(context: sourceContext)
        defer { try? FileManager.default.removeItem(at: backupURL) }

        try await BackupService().importBackup(from: backupURL, context: destContext)

        let documents = try destContext.fetch(FetchDescriptor<DocumentRecord>())
        #expect(documents.count == 3)
        #expect(Set(documents.map(\.title)) == Set(["Doc 0", "Doc 1", "Doc 2"]))
    }
}
