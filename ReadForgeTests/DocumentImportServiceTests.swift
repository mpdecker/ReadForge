import Testing
import Foundation
@testable import ReadForge

struct DocumentImportServiceTests {
    let svc = DocumentImportService()

    // MARK: - Extension validation

    @Test func unsupportedExtensionThrows() throws {
        let url = URL(fileURLWithPath: "/tmp/document.docx")
        #expect(throws: ImportError.unsupportedFormat) {
            try svc.importDocument(from: url)
        }
    }

    @Test func pagesExtensionThrows() throws {
        let url = URL(fileURLWithPath: "/tmp/notes.pages")
        #expect(throws: ImportError.unsupportedFormat) {
            try svc.importDocument(from: url)
        }
    }

    @Test func missingFileThrows() throws {
        let url = URL(fileURLWithPath: "/nonexistent/path/document.pdf")
        #expect(throws: ImportError.fileMissing) {
            try svc.importDocument(from: url)
        }
    }

    // MARK: - Successful import

    @Test func importCopiesFileToSandbox() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        // Create a minimal file (content doesn't matter for copy test)
        try Data("%PDF-1.4".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let record = try svc.importDocument(from: tmp)
        defer { try? FileManager.default.removeItem(at: record.fileURL) }

        #expect(FileManager.default.fileExists(atPath: record.fileURL.path))
        // Destination must be inside the sandbox folder, not the tmp location
        #expect(record.fileURL.path != tmp.path)
    }

    @Test func importPreservesTitle() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("My Document.pdf")
        try Data("%PDF-1.4".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let record = try svc.importDocument(from: tmp)
        defer { try? FileManager.default.removeItem(at: record.fileURL) }

        #expect(record.title == "My Document")
    }

    @Test func importDecodesPercentEncodedTitle() throws {
        let encoded = "My%20Encoded%20Doc.pdf"
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(encoded)
        try Data("%PDF-1.4".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let record = try svc.importDocument(from: tmp)
        defer { try? FileManager.default.removeItem(at: record.fileURL) }

        #expect(record.title == "My Encoded Doc")
    }

    @Test func importWithEmptyNameFallsBackToUntitled() throws {
        // A URL with a bare extension would have an empty stem — simulate with ".pdf"
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(".pdf")
        try Data("%PDF-1.4".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let record = try svc.importDocument(from: tmp)
        defer { try? FileManager.default.removeItem(at: record.fileURL) }

        #expect(record.title == "Untitled")
    }

    // MARK: - sandboxURL

    @Test func sandboxURLCreatesDirectory() throws {
        let url = try DocumentImportService.sandboxURL()
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        #expect(exists)
        #expect(isDir.boolValue)
    }

    @Test func sandboxURLIsIdempotent() throws {
        let url1 = try DocumentImportService.sandboxURL()
        let url2 = try DocumentImportService.sandboxURL()
        #expect(url1 == url2)
    }
}
