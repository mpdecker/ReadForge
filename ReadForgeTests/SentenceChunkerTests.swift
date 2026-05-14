import Testing
@testable import ReadForge

struct SentenceChunkerTests {
    let chunker = SentenceChunker()

    // MARK: - Empty input

    @Test func emptyStringReturnsEmpty() {
        #expect(chunker.chunk("").isEmpty)
    }

    @Test func whitespaceOnlyReturnsEmpty() {
        #expect(chunker.chunk("   \n  ").isEmpty)
    }

    // MARK: - Short text

    @Test func shortSingleSentenceIsOneChunk() {
        let result = chunker.chunk("Hello world.")
        #expect(result.count == 1)
        #expect(result[0] == "Hello world.")
    }

    // MARK: - Merging

    @Test func shortSentencesMergedIntoOneChunk() {
        // Two short sentences should merge into one chunk (combined < 800 chars)
        let result = chunker.chunk("One. Two.")
        #expect(result.count == 1)
        #expect(result[0].contains("One."))
        #expect(result[0].contains("Two."))
    }

    @Test func sentencesMergingStopsAtMaxLength() {
        // Generate many short sentences totalling well over 800 chars
        let sentences = (1...30).map { "Sentence number \($0) is here." }.joined(separator: " ")
        let result = chunker.chunk(sentences)
        for chunk in result {
            #expect(chunk.count <= 800)
        }
    }

    // MARK: - Hard split

    @Test func singleLongWordsSplitAtWordBoundary() {
        // One massive "sentence" — no sentence boundaries, over maxLength
        let longText = Array(repeating: "word", count: 300).joined(separator: " ")
        let result = chunker.chunk(longText)
        #expect(!result.isEmpty)
        for chunk in result {
            #expect(chunk.count <= 800)
        }
    }

    @Test func hardSplitProducesNoEmptyChunks() {
        let longText = Array(repeating: "x", count: 2000).joined()
        let result = chunker.chunk(longText)
        for chunk in result {
            #expect(!chunk.isEmpty)
        }
    }

    // MARK: - No chunk exceeds max length

    @Test func noChunkExceedsMaxLength() {
        let text = """
        The quick brown fox jumps over the lazy dog. \
        Pack my box with five dozen liquor jugs. \
        How vexingly quick daft zebras jump. \
        The five boxing wizards jump quickly.
        """
        let repeated = Array(repeating: text, count: 20).joined(separator: " ")
        let result = chunker.chunk(repeated)
        for chunk in result {
            #expect(chunk.count <= 800)
        }
    }
}
