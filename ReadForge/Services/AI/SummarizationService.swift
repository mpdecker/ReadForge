import Foundation
import NaturalLanguage

/// Document/section summaries (CLAUDE.md v1.5 milestone: "local LLM cleanup, summaries, Ask
/// mode").
///
/// Scope note (same tradeoff as `TextCleanupAIService` and `DocumentSearchService`): a
/// generative summary needs a bundled LLM, which needs multi-gigabyte model weights this coding
/// session can't fetch or verify running on-device. This implements *extractive* summarization
/// instead — a real, well-established technique (a simplified TextRank): score every sentence by
/// how semantically central it is to the rest of the text using on-device `NLEmbedding` vectors,
/// then return the highest-scoring sentences in their original order. Every sentence in the
/// output is verbatim from the source, so — unlike a generative summary — there's no
/// hallucination risk, which is a reasonable tradeoff for a reading app.
struct SummarizationService: Sendable {
    enum SummarizationError: LocalizedError {
        case tooShort
        var errorDescription: String? { "This section is too short to summarize." }
    }

    /// Bounds the O(n²) pairwise-similarity pass — a section already caps at ~3,000 words
    /// (`PDFSectionDetectionService.wordsPerChunk`), so this only ever trims pathological cases.
    private let maxSentencesConsidered = 150

    func summarize(_ text: String, maxSentences: Int = 5) throws -> String {
        let allSentences = SentenceChunker.sentences(in: text).filter { $0.count >= 20 }
        guard allSentences.count > maxSentences else {
            guard !allSentences.isEmpty else { throw SummarizationError.tooShort }
            return allSentences.joined(separator: " ")
        }

        let sentences = Array(allSentences.prefix(maxSentencesConsidered))

        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
            // No embedding model available for this locale — fall back to a simple positional
            // heuristic (first sentence of each roughly-equal chunk), still real text, just a
            // cruder selection than centrality scoring.
            return positionalFallback(sentences, maxSentences: maxSentences)
        }

        let scores = centralityScores(for: sentences, using: embedding)

        let rankedIndices = scores.indices.sorted { scores[$0] > scores[$1] }
        let topIndices = Set(rankedIndices.prefix(maxSentences))
        let ordered = sentences.indices.filter { topIndices.contains($0) }.map { sentences[$0] }

        return ordered.joined(separator: " ")
    }

    // MARK: - Private

    /// Degree-centrality score per sentence: how similar it is, on average, to every other
    /// sentence — a simplified stand-in for a full TextRank eigenvector iteration that's cheap
    /// enough to run inline and works well for section-length text.
    private func centralityScores(for sentences: [String], using embedding: NLEmbedding) -> [Double] {
        var scores = [Double](repeating: 0, count: sentences.count)
        guard sentences.count > 1 else { return scores }

        for i in 0..<sentences.count {
            for j in (i + 1)..<sentences.count {
                let distance = embedding.distance(between: sentences[i], and: sentences[j], distanceType: .cosine)
                guard distance.isFinite else { continue }
                let similarity = max(0, 1 - distance / 2)
                scores[i] += similarity
                scores[j] += similarity
            }
        }
        return scores
    }

    private func positionalFallback(_ sentences: [String], maxSentences: Int) -> String {
        guard sentences.count > maxSentences else { return sentences.joined(separator: " ") }
        let stride = max(1, sentences.count / maxSentences)
        var picked: [String] = []
        var index = 0
        while picked.count < maxSentences && index < sentences.count {
            picked.append(sentences[index])
            index += stride
        }
        return picked.joined(separator: " ")
    }
}
