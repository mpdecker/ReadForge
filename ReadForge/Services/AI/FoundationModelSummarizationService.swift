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

        // Sections built from a PDF's own outline/bookmarks (`PDFSectionDetectionService
        // .fromOutline`, the preferred path whenever the PDF has one) have NO size cap — unlike
        // the heuristic fallback path, which caps around 3,000 words. A section spanning a whole
        // chapter of a coarsely-bookmarked book can run tens of thousands of characters. This
        // used to just bail (`text.count < 12_000 else { return nil }`), which meant every large
        // chapter *always* silently fell back to the lower-quality extractive summary — with the
        // real model fully available — with nothing to indicate why. A bounded excerpt (start +
        // middle + end, not just a truncated prefix) still lets the real summarizer run on
        // representative content instead of giving up outright.
        let excerpt = Self.boundedExcerpt(of: text, limit: 12_000)

        let session = LanguageModelSession(instructions: Self.instructions(maxSentences: maxSentences))
        do {
            let response = try await session.respond(to: excerpt)
            let candidate = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return isValidSummary(candidate, against: text) ? candidate : nil
        } catch {
            ReadForgeLogger.error(category: "AI", message: "Foundation Model summarization failed", error: error)
            return nil
        }
    }

    /// Start + middle + end, rather than a plain prefix truncation — a summary built only from
    /// the first N characters of a long chapter would be biased toward its opening and miss
    /// everything the chapter actually concludes with.
    private static func boundedExcerpt(of text: String, limit: Int) -> String {
        guard text.count > limit else { return text }

        let partLimit = limit / 3
        let start = String(text.prefix(partLimit))
        let end = String(text.suffix(partLimit))

        let midpoint = text.index(text.startIndex, offsetBy: text.count / 2)
        let midStart = text.index(midpoint, offsetBy: -partLimit / 2, limitedBy: text.startIndex) ?? text.startIndex
        let midEnd = text.index(midStart, offsetBy: partLimit, limitedBy: text.endIndex) ?? text.endIndex
        let middle = String(text[midStart..<midEnd])

        return "\(start)\n\n[…]\n\n\(middle)\n\n[…]\n\n\(end)"
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

        // Checked as a *prefix*, not a substring — a section that discusses or quotes a
        // subsection literally titled "Summary:" (common in academic papers/reports) could
        // otherwise produce a correct, compliant summary that gets rejected purely for
        // containing that substring somewhere in the middle.
        let lowered = candidate.lowercased()
        let commentaryPrefixes = ["as an ai", "i cannot", "i'm sorry", "here is a summary", "here's a summary", "summary:"]
        guard !commentaryPrefixes.contains(where: lowered.hasPrefix) else { return false }
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
