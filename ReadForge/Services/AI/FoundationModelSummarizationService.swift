import Foundation
import FoundationModels

/// Real generative summarization using Apple's on-device Foundation Model (CLAUDE.md v1.5:
/// "summaries"), for devices where it's actually available — see
/// `FoundationModelTextCleanupService`'s doc comment for how availability is checked and why
/// this needs no deployment-target change. `SummarizationService` (extractive, TextRank-style)
/// remains the fallback for everything else and is what this always degrades to on failure.
@available(iOS 26.0, *)
struct FoundationModelSummarizationService {
    enum SummarizationError: Error {
        case unavailable
    }

    static var isSystemModelAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Returns `nil` (never throws) when the model isn't available or the result fails
    /// validation, so callers can fall back to the extractive summarizer exactly like
    /// `TieredTextCleanupService` falls back to the NLP cleanup pass.
    func summarize(_ text: String, maxSentences: Int = 5) async -> String? {
        guard Self.isSystemModelAvailable else { return nil }
        guard text.count < 12_000 else { return nil } // context-window safety margin

        let session = LanguageModelSession(instructions: Self.instructions(maxSentences: maxSentences))
        do {
            let response = try await session.respond(to: text)
            let candidate = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return isValidSummary(candidate, against: text) ? candidate : nil
        } catch {
            ReadForgeLogger.error(category: "AI", message: "Foundation Model summarization failed", error: error)
            return nil
        }
    }

    private func isValidSummary(_ candidate: String, against original: String) -> Bool {
        guard !candidate.isEmpty else { return false }
        // A summary that isn't meaningfully shorter than the source isn't actually summarizing —
        // this is the opposite check from cleanup's validator (which requires staying *close*
        // to the original length), so it's intentionally not shared with
        // `AICleanupOutputValidator`.
        guard Double(candidate.count) <= Double(original.count) * 0.6 else { return false }
        let markdownMarkers = ["```", "##", "- [ ]"]
        guard !markdownMarkers.contains(where: candidate.contains) else { return false }
        let commentaryPhrases = ["as an ai", "i cannot", "i'm sorry", "here is a summary", "here's a summary", "summary:"]
        let lowered = candidate.lowercased()
        guard !commentaryPhrases.contains(where: lowered.contains) else { return false }
        return true
    }

    private static func instructions(maxSentences: Int) -> String {
        """
        Summarize the given text for someone about to listen to it as narrated audio. Keep it \
        to at most \(maxSentences) sentences, preserve key names and facts, and do not add \
        information that isn't in the text. Return only the summary — no preamble, no heading.
        """
    }
}
