import Testing
import Foundation
@testable import ReadForge

struct TextCleanupAIServiceTests {
    let svc = TextCleanupAIService()

    // Regression test: `enhancedClean` used to join every sentence in the whole input with a
    // single space, erasing "\n\n" paragraph breaks. That silently broke
    // `PDFSectionDetectionService.fromHeuristics`'s heading detection (it looks for short,
    // title-cased *paragraphs*) and oversized `DocumentSearchService`/`SummarizationService`
    // passages, the moment the "Enhanced Cleanup" toggle actually took effect.
    @Test func paragraphBreaksArePreserved() async throws {
        let text = """
        Chapter One

        This is the first paragraph. It has two sentences in it.

        This is a second, distinct paragraph. It should stay separate from the first.
        """
        let result = await svc.runCleanup(on: text)
        let cleaned = try #require(result)
        #expect(cleaned.contains("\n\n"), "Paragraph breaks should survive the enhancement pass")

        let paragraphs = cleaned.components(separatedBy: "\n\n").filter { !$0.isEmpty }
        #expect(paragraphs.count >= 3, "Should still have three distinct paragraphs (heading + 2 body)")
    }

    @Test func sentencesWithinAParagraphAreRejoined() async throws {
        // A stray layout line break splitting one sentence in half, within a single paragraph.
        let text = "This is a single sentence that got\nbroken by a layout artifact in the middle of it."
        let result = await svc.runCleanup(on: text)
        let cleaned = try #require(result)
        #expect(!cleaned.contains("that got\nbroken"), "The mid-sentence line break should be rejoined")
    }

    @Test func emptyInputReturnsNil() async throws {
        let result = await svc.runCleanup(on: "")
        #expect(result == nil, "Empty input should fail validation and fall back to deterministic cleanup")
    }
}
