import Testing
import Foundation
@testable import ReadForge

struct SectionDetectionServiceTests {
    let svc = PDFSectionDetectionService()

    // MARK: - isHeading

    @Test func allCapsIsHeading() {
        #expect(svc.isHeading("INTRODUCTION"))
    }

    @Test func titleCaseIsHeading() {
        #expect(svc.isHeading("The First Chapter"))
    }

    @Test func lowercaseSentenceIsNotHeading() {
        #expect(!svc.isHeading("this is a regular sentence with many words that keeps going."))
    }

    @Test func headingWithTrailingPeriodIsNotHeading() {
        #expect(!svc.isHeading("Introduction."))
    }

    @Test func tooManyWordsIsNotHeading() {
        // 11 words — one past the documented ≤10-word limit.
        #expect(!svc.isHeading("The Quick Brown Fox Jumps Over The Very Lazy Dog Today"))
    }

    @Test func exactlyTenWordsIsHeading() {
        #expect(svc.isHeading("The Quick Brown Fox Jumps Over The Lazy Dog Today"))
    }

    @Test func tooShortIsNotHeading() {
        #expect(!svc.isHeading("A"))
    }

    @Test func emptyStringIsNotHeading() {
        #expect(!svc.isHeading(""))
    }

    @Test func mixedCaseSentenceIsNotHeading() {
        #expect(!svc.isHeading("some text That is Mixed"))
    }

    // MARK: - detect with empty input

    @Test func emptyPagesReturnsEmpty() {
        let result = svc.detect(pages: [], outlineEntries: [], cleanedPages: [])
        #expect(result.isEmpty)
    }

    @Test func emptyCleanedTextReturnsEmpty() {
        let result = svc.detect(pages: [], outlineEntries: [], cleanedPages: [PageText(pageNumber: 1, text: "   ")])
        #expect(result.isEmpty)
    }

    // MARK: - Outline-based detection

    @Test func outlineProducesCorrectSectionCount() {
        let pages = (1...5).map { PageText(pageNumber: $0, text: "Content of page \($0).") }
        let outline: [(title: String, pageIndex: Int)] = [
            (title: "Introduction", pageIndex: 0),
            (title: "Chapter One", pageIndex: 2),
            (title: "Conclusion", pageIndex: 4)
        ]
        let result = svc.detect(pages: pages, outlineEntries: outline, cleanedPages: pages)
        #expect(result.count == 3)
        #expect(result[0].title == "Introduction")
        #expect(result[1].title == "Chapter One")
        #expect(result[2].title == "Conclusion")
    }

    @Test func outlineEntriesAreOrdered() {
        let pages = (1...4).map { PageText(pageNumber: $0, text: "Page \($0)") }
        // Supply outline out of order
        let outline: [(title: String, pageIndex: Int)] = [
            (title: "Chapter Two", pageIndex: 2),
            (title: "Chapter One", pageIndex: 0)
        ]
        let result = svc.detect(pages: pages, outlineEntries: outline, cleanedPages: pages)
        #expect(result[0].title == "Chapter One")
        #expect(result[1].title == "Chapter Two")
    }

    @Test func outOfBoundsOutlineEntriesFiltered() {
        let pages = [PageText(pageNumber: 1, text: "Only one page.")]
        let outline: [(title: String, pageIndex: Int)] = [
            (title: "Valid", pageIndex: 0),
            (title: "Invalid", pageIndex: 99)  // out of bounds
        ]
        let result = svc.detect(pages: pages, outlineEntries: outline, cleanedPages: pages)
        #expect(result.count == 1)
        #expect(result[0].title == "Valid")
    }

    @Test func sectionEndPageClamped() {
        let pages = (1...3).map { PageText(pageNumber: $0, text: "Page \($0)") }
        let outline: [(title: String, pageIndex: Int)] = [(title: "Only", pageIndex: 0)]
        let result = svc.detect(pages: pages, outlineEntries: outline, cleanedPages: pages)
        #expect(result.count == 1)
        // End page should be clamped to last page (index 2 → page 3)
        #expect(result[0].endPage == 3)
    }

    // Regression test: a parent outline entry (e.g. "Chapter 1") and its first subsection entry
    // (e.g. "1.1 Introduction") commonly point at the exact same destination page. This used to
    // truncate the parent's section to just that one page while the child section ALSO started
    // there — the page's text was narrated twice in a row. The more specific (child) title
    // should survive with the full span; the swallowed parent should not produce a section.
    @Test func outlineEntriesSharingAPageDoNotDuplicateContent() {
        let pages = (1...4).map { PageText(pageNumber: $0, text: "Content of page \($0).") }
        let outline: [(title: String, pageIndex: Int)] = [
            (title: "Chapter 1", pageIndex: 0),
            (title: "1.1 Introduction", pageIndex: 0),
            (title: "Chapter 2", pageIndex: 2)
        ]
        let result = svc.detect(pages: pages, outlineEntries: outline, cleanedPages: pages)
        #expect(result.count == 2, "The swallowed parent entry should not produce its own section")
        #expect(result[0].title == "1.1 Introduction")
        #expect(result[0].startPage == 1)
        #expect(result[0].endPage == 2, "The surviving entry should own the full span up to the next distinct page")
        #expect(result[1].title == "Chapter 2")
        // No page's text should appear twice across sections.
        let allText = result.map(\.rawText).joined()
        #expect(allText.components(separatedBy: "Content of page 1.").count - 1 == 1)
    }

    // MARK: - Heuristic detection

    @Test func heuristicFallbackProducesAtLeastOneSection() {
        let text = Array(repeating: "This is a body paragraph with enough words.", count: 50).joined(separator: "\n\n")
        let result = svc.detect(pages: [], outlineEntries: [], cleanedPages: [PageText(pageNumber: 1, text: text)])
        #expect(!result.isEmpty)
    }

    @Test func heuristicHeadingBecomesTitle() {
        let text = "INTRODUCTION\n\n" + Array(repeating: "Body text here.", count: 20).joined(separator: " ")
        let result = svc.detect(pages: [], outlineEntries: [], cleanedPages: [PageText(pageNumber: 1, text: text)])
        #expect(result.first?.title == "INTRODUCTION")
    }

    // Regression test: a heading found before enough words had accumulated to flush used to
    // unconditionally overwrite `pendingTitle`, silently discarding an earlier, outer heading
    // (e.g. "Chapter 1" immediately followed by "1.1 Overview") — the resulting section ended up
    // titled only after the later heading even though it contains the chapter-opening content.
    @Test func firstHeadingSurvivesWhenAnotherHeadingFollowsBeforeFlush() {
        let text = "CHAPTER ONE\n\nOverview\n\n" + Array(repeating: "Body text here.", count: 20).joined(separator: " ")
        let result = svc.detect(pages: [], outlineEntries: [], cleanedPages: [PageText(pageNumber: 1, text: text)])
        #expect(result.first?.title == "CHAPTER ONE")
    }

    @Test func heuristicSectionsHaveSequentialOrder() {
        // Generate text with a heading every ~3000 words
        var chunks: [String] = []
        for i in 1...3 {
            chunks.append("CHAPTER \(i)")
            chunks.append(Array(repeating: "word", count: 3_100).joined(separator: " "))
        }
        let text = chunks.joined(separator: "\n\n")
        let result = svc.detect(pages: [], outlineEntries: [], cleanedPages: [PageText(pageNumber: 1, text: text)])
        for (i, section) in result.enumerated() {
            #expect(section.order == i)
        }
    }
}
