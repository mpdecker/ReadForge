import Foundation
import FoundationModels

/// Real generative answers for Ask Mode (CLAUDE.md Phase 10/14: "local RAG with embeddings") —
/// the generative half `DocumentSearchService`'s doc comment said wasn't buildable without a
/// bundled LLM. On devices where Apple's on-device Foundation Model is available, this
/// synthesizes an actual answer grounded in `DocumentSearchService`'s retrieved passages, with
/// explicit instructions not to use outside knowledge — a real, if narrower, RAG pipeline: the
/// retrieval half was already real, only the generation half was missing.
@available(iOS 26.0, *)
struct FoundationModelAnswerService {
    static var isSystemModelAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Returns `nil` (never throws) when the model isn't available, there are no passages to
    /// ground the answer in, or the call fails — callers fall back to just showing the ranked
    /// passages themselves, exactly as Ask Mode already did before this existed.
    func answer(question: String, passages: [DocumentSearchService.SearchResult]) async -> String? {
        guard Self.isSystemModelAvailable, !passages.isEmpty else { return nil }

        let context = passages.enumerated()
            .map { "[\($0.offset + 1)] (\($0.element.sectionTitle)) \($0.element.passage)" }
            .joined(separator: "\n\n")
        guard context.count < 12_000 else { return nil } // context-window safety margin

        let session = LanguageModelSession(instructions: Self.instructions)
        do {
            let response = try await session.respond(to: "Passages:\n\(context)\n\nQuestion: \(question)")
            let candidate = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return candidate.isEmpty ? nil : candidate
        } catch {
            ReadForgeLogger.error(category: "AI", message: "Foundation Model Ask Mode answer failed", error: error)
            return nil
        }
    }

    private static let instructions = """
    Answer the user's question using ONLY the numbered passages provided — never use outside \
    knowledge or guess. If the passages don't contain enough information to answer, say so \
    plainly rather than speculating. Keep the answer concise (2-4 sentences), and reference \
    passage numbers like [1] where relevant.
    """
}
