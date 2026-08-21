import Foundation

/// Shared by every `AIModelManaging` cleanup implementation (both the Foundation Model path and
/// the NaturalLanguage fallback) — CLAUDE.md's "Always validate LLM output: not empty, not much
/// shorter than input, no markdown, no assistant commentary. Fall back to deterministic clean
/// text on failure." Factored out so the two implementations can't silently drift on what
/// "valid" means.
enum AICleanupOutputValidator {
    static func isValid(_ candidate: String, against original: String) -> Bool {
        guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        // Losing more than 25% of the content suggests something went wrong, not cleanup.
        guard Double(candidate.count) >= Double(original.count) * 0.75 else { return false }
        let markdownMarkers = ["```", "##", "**", "- [ ]", "> "]
        guard !markdownMarkers.contains(where: candidate.contains) else { return false }
        let commentaryPhrases = ["as an ai", "i cannot", "i'm sorry", "here is the cleaned", "here's the cleaned"]
        let lowered = candidate.lowercased()
        guard !commentaryPhrases.contains(where: lowered.contains) else { return false }
        return true
    }
}
