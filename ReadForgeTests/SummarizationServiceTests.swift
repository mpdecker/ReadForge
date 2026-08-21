import Testing
@testable import ReadForge

struct SummarizationServiceTests {
    let svc = SummarizationService()

    @Test func shortTextThrowsTooShort() {
        #expect(throws: SummarizationService.SummarizationError.self) {
            try svc.summarize("Too short.")
        }
    }

    @Test func textUnderSentenceLimitReturnsEverything() throws {
        let text = "This is the first sentence here. This is the second sentence here."
        let result = try svc.summarize(text, maxSentences: 5)
        #expect(result.contains("first sentence"))
        #expect(result.contains("second sentence"))
    }

    @Test func longerTextReturnsFewerSentencesThanSource() throws {
        let sentences = (1...20).map { "This is sentence number \($0) with some extra words to pad it out nicely." }
        let text = sentences.joined(separator: " ")
        let result = try svc.summarize(text, maxSentences: 5)

        let resultSentenceCount = SentenceChunker.sentences(in: result).count
        #expect(resultSentenceCount <= 5)
        #expect(resultSentenceCount > 0)
    }

    @Test func summarySentencesAreVerbatimFromSource() throws {
        // Extractive summarization must never fabricate text — every sentence in the result
        // should appear in the source, unmodified.
        let sentences = (1...10).map { "Distinctive sentence marker number \($0) appears right here for testing purposes." }
        let text = sentences.joined(separator: " ")
        let result = try svc.summarize(text, maxSentences: 3)

        for resultSentence in SentenceChunker.sentences(in: result) {
            #expect(text.contains(resultSentence), "Summary sentence should be verbatim from source: \(resultSentence)")
        }
    }

    @Test func veryShortSentencesAreFilteredOut() throws {
        // Short fragments (headers, page numbers) shouldn't dominate a summary.
        let text = ([
            "Ch. 1",
            "This is a substantial sentence describing the actual content of the chapter in detail.",
            "Pg 2",
            "Another substantial sentence that continues describing the chapter's real content thoroughly."
        ] + Array(repeating: "Filler sentence used just to push the count above the summarization threshold value.", count: 6)).joined(separator: " ")

        let result = try svc.summarize(text, maxSentences: 3)
        #expect(!result.contains("Ch. 1"))
        #expect(!result.contains("Pg 2"))
    }
}
