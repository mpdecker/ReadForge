import Foundation
import Testing
@testable import ReadForge

struct PDFExtractionServiceTests {
    let svc = PDFExtractionService()

    // MARK: - isLikelyScanned

    @Test func denseTextIsNotScanned() {
        let pages = (1...10).map { i in
            PageText(pageNumber: i, text: String(repeating: "a", count: 500))
        }
        #expect(!svc.isLikelyScanned(pages))
    }

    @Test func sparseTextIsLikelyScanned() {
        // < 50 chars/page average → scanned
        let pages = (1...10).map { i in
            PageText(pageNumber: i, text: String(repeating: "a", count: 10))
        }
        #expect(svc.isLikelyScanned(pages))
    }

    @Test func exactlyAtThresholdNotScanned() {
        // Exactly 50 chars/page is NOT scanned (< 50 is the condition)
        let pages = (1...5).map { i in
            PageText(pageNumber: i, text: String(repeating: "a", count: 50))
        }
        #expect(!svc.isLikelyScanned(pages))
    }

    @Test func emptyPagesNotScanned() {
        #expect(!svc.isLikelyScanned([]))
    }

    @Test func mixedDensityUsesAverage() {
        // 9 pages dense + 1 page empty → average well above 50
        var pages = (1...9).map { i in
            PageText(pageNumber: i, text: String(repeating: "x", count: 300))
        }
        pages.append(PageText(pageNumber: 10, text: ""))
        #expect(!svc.isLikelyScanned(pages))
    }

    // MARK: - extractMetadata with bad URL

    @Test func extractMetadataOnMissingFileReturnsNilFields() {
        let badURL = URL(fileURLWithPath: "/nonexistent/path/to.pdf")
        let metadata = svc.extractMetadata(from: badURL)
        #expect(metadata.title == nil)
        #expect(metadata.author == nil)
        #expect(metadata.pageCount == 0)
    }

    // MARK: - extractPages with bad URL

    @Test func extractPagesOnMissingFileThrows() throws {
        let badURL = URL(fileURLWithPath: "/nonexistent/path/to.pdf")
        #expect(throws: (any Error).self) {
            try svc.extractPages(from: badURL)
        }
    }

    // MARK: - outline with bad URL

    @Test func outlineOnMissingFileReturnsEmpty() {
        let badURL = URL(fileURLWithPath: "/nonexistent/path/to.pdf")
        #expect(svc.outline(from: badURL).isEmpty)
    }
}
