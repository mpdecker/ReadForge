import Foundation
import NaturalLanguage

/// Ask Mode's retrieval layer (CLAUDE.md Phase 10/14: "local RAG with embeddings") — finds and
/// ranks the passages most relevant to a typed question using Apple's on-device `NLEmbedding`
/// sentence vectors. No network access, no server, fully on-device per CLAUDE.md's privacy
/// rules.
///
/// This is the retrieval half of RAG; `FoundationModelAnswerService` (in `AskModeView`) is the
/// generation half, synthesizing an actual answer grounded in the passages this returns — real
/// on devices with Apple's on-device Foundation Model available (iOS 26+, eligible hardware),
/// falling back to just showing these ranked passages directly everywhere else. Either way, the
/// results here are the real, checkable source: a generated answer is never presented without
/// them.
struct DocumentSearchService: Sendable {
    struct SearchResult: Identifiable, Sendable {
        let id = UUID()
        let sectionId: UUID
        let sectionTitle: String
        let passage: String
        let relevance: Double
    }

    /// A plain, `Sendable` snapshot of the section text to search — `SectionRecord` is a
    /// SwiftData `@Model` reference type tied to its `ModelContext`'s actor, so it isn't safe
    /// to touch from a background task. Callers build this on the main actor first, then hand
    /// it to `search`, which can run off the main actor (search over a large document
    /// otherwise runs synchronously on the UI thread with no spinner and no way to cancel).
    struct SearchableSection: Sendable {
        let id: UUID
        let title: String
        let text: String

        init(id: UUID, title: String, text: String) {
            self.id = id
            self.title = title
            self.text = text
        }
    }

    func search(query: String, in sections: [SearchableSection], limit: Int = 5) -> [SearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        // Reuses `SentenceChunker`'s sentence-aware, hard-split-guaranteed chunking (300–800
        // chars) instead of a hand-rolled paragraph merge with no upper bound — a single dense
        // paragraph longer than the target length used to become one oversized, un-split
        // passage, which both degrades relevance ranking (NLEmbedding is tuned for
        // sentence-length input) and duplicated logic `SentenceChunker` already has.
        let chunker = SentenceChunker()
        let passages = sections.flatMap { section in
            chunker.chunk(section.text).map { (section, $0) }
        }
        guard !passages.isEmpty else { return [] }

        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english),
              let queryVector = embedding.vector(for: trimmedQuery)
        else {
            return keywordSearch(query: trimmedQuery, in: passages, limit: limit)
        }

        // Each passage's vector is computed exactly once and compared against the single
        // query vector computed above — `NLEmbedding.distance(between:and:)` would otherwise
        // re-embed the (identical) query text on every one of the N comparisons.
        let scored: [(section: SearchableSection, passage: String, similarity: Double)] = passages.compactMap { section, passage in
            guard let passageVector = embedding.vector(for: passage) else { return nil }
            let similarity = cosineSimilarity(queryVector, passageVector)
            guard similarity.isFinite else { return nil }
            return (section, passage, similarity)
        }

        guard !scored.isEmpty else {
            return keywordSearch(query: trimmedQuery, in: passages, limit: limit)
        }

        let ranked = scored.sorted { $0.similarity > $1.similarity }
        let top = ranked.prefix(limit)

        var results: [SearchResult] = []
        for entry in top {
            results.append(SearchResult(
                sectionId: entry.section.id,
                sectionTitle: entry.section.title,
                passage: entry.passage,
                relevance: max(0, entry.similarity)
            ))
        }
        return results
    }

    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }

    // MARK: - Fallback

    /// Used only if `NLEmbedding.sentenceEmbedding` is unavailable for the device's locale.
    private func keywordSearch(
        query: String,
        in passages: [(SearchableSection, String)],
        limit: Int
    ) -> [SearchResult] {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return [] }

        var scored: [(section: SearchableSection, passage: String, hits: Int)] = []
        for (section, passage) in passages {
            let lowered = passage.lowercased()
            var hits = 0
            for term in terms where lowered.contains(term) { hits += 1 }
            if hits > 0 { scored.append((section, passage, hits)) }
        }

        let ranked = scored.sorted { $0.hits > $1.hits }
        let top = ranked.prefix(limit)

        var results: [SearchResult] = []
        for entry in top {
            let relevance: Double = Double(entry.hits) / Double(terms.count)
            results.append(SearchResult(
                sectionId: entry.section.id,
                sectionTitle: entry.section.title,
                passage: entry.passage,
                relevance: relevance
            ))
        }
        return results
    }
}
