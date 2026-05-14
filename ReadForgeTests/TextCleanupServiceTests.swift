import Testing
@testable import ReadForge

struct TextCleanupServiceTests {
    let svc = TextCleanupService()

    // MARK: - Empty input

    @Test func emptyPages() {
        #expect(svc.clean([]) == "")
    }

    @Test func singlePageEmptyText() {
        let result = svc.clean([PageText(pageNumber: 1, text: "   ")])
        #expect(result.isEmpty)
    }

    // MARK: - CRLF normalisation

    @Test func crlfNormalised() {
        let pages = [PageText(pageNumber: 1, text: "Line one\r\nLine two\rLine three")]
        let result = svc.clean(pages)
        #expect(!result.contains("\r"))
    }

    // MARK: - Hyphenated line-break joining

    @Test func hyphenatedLineBreakJoined() {
        let pages = [PageText(pageNumber: 1, text: "algo-\nrithm is fast")]
        let result = svc.clean(pages)
        #expect(result.contains("algorithm"))
        #expect(!result.contains("-\n"))
    }

    // MARK: - Soft-wrapped line joining

    @Test func softWrappedLinesJoined() {
        let pages = [PageText(pageNumber: 1, text: "The quick brown\nfox jumps over\nthe lazy dog.")]
        let result = svc.clean(pages)
        #expect(result.contains("The quick brown fox jumps over the lazy dog."))
    }

    // MARK: - Citation removal

    @Test func singleCitationRemoved() {
        let pages = [PageText(pageNumber: 1, text: "This is a fact [1] that we know.")]
        let result = svc.clean(pages)
        #expect(!result.contains("[1]"))
        #expect(result.contains("This is a fact"))
        #expect(result.contains("that we know."))
    }

    @Test func rangedCitationRemoved() {
        let pages = [PageText(pageNumber: 1, text: "Evidence [1-3] supports this.")]
        let result = svc.clean(pages)
        #expect(!result.contains("[1-3]"))
    }

    @Test func commaSeparatedCitationRemoved() {
        let pages = [PageText(pageNumber: 1, text: "Multiple sources [1,2,3] agree.")]
        let result = svc.clean(pages)
        #expect(!result.contains("[1,2,3]"))
    }

    // MARK: - Whitespace collapse

    @Test func multipleSpacesCollapsed() {
        let pages = [PageText(pageNumber: 1, text: "word1    word2   word3")]
        let result = svc.clean(pages)
        #expect(result.contains("word1 word2 word3"))
    }

    // MARK: - Header/footer removal

    @Test func headerAndFooterRemovedWhenRepeated() {
        // Create 5 pages where first line is always "My Book Title"
        let header = "My Book Title"
        let footer = "Page 42"
        let pages = (1...5).map { i in
            PageText(pageNumber: i, text: "\(header)\nUnique content for page \(i).\n\(footer)")
        }
        let result = svc.clean(pages)
        // Header and footer should be stripped (appear on 100% of pages > threshold)
        #expect(!result.contains(header))
        #expect(!result.contains(footer))
        // Unique content should remain
        #expect(result.contains("Unique content"))
    }

    @Test func headerNotRemovedWithTooFewPages() {
        // With ≤3 pages, repeatedLines returns empty set — nothing is removed
        let header = "My Book Title"
        let pages = (1...3).map { i in
            PageText(pageNumber: i, text: "\(header)\nContent \(i)")
        }
        let result = svc.clean(pages)
        // Header should NOT be removed (3 pages ≤ threshold)
        #expect(result.contains(header))
    }

    // MARK: - Paragraph preservation

    @Test func doubleNewlinePreservesParagraphBreak() {
        let pages = [PageText(pageNumber: 1, text: "First paragraph.\n\nSecond paragraph.")]
        let result = svc.clean(pages)
        // Both paragraphs should be present
        #expect(result.contains("First paragraph."))
        #expect(result.contains("Second paragraph."))
    }
}
