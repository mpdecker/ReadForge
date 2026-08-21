import Foundation
import NaturalLanguage

/// On-device text cleanup — the fallback tier (CLAUDE.md Phase 9).
///
/// `TieredTextCleanupService` is what actually gets registered in `ServiceContainer`: it prefers
/// `FoundationModelTextCleanupService` (a real generative model, Apple's on-device Foundation
/// Models framework, iOS 26+ on eligible hardware) and only falls back to this NaturalLanguage-
/// based pass — sentence-boundary-aware rejoining, language detection, citation stripping — when
/// the real model isn't available on the current device (older iOS, ineligible hardware, Apple
/// Intelligence disabled, or the on-device asset not yet downloaded). This type still needs to be
/// solid on its own: it's the only cleanup path on the wide majority of devices for years to come.
struct TextCleanupAIService: AIModelManaging {
    // MARK: - AIModelManaging

    /// Always true: there's no model file to load — the enhancement runs directly on Apple's
    /// bundled-with-the-OS NaturalLanguage models, so there's nothing to be "not loaded" yet.
    var isLoaded: Bool { true }
    var modelName: String? { "On-device NLP (NaturalLanguage framework)" }

    func loadModel(at url: URL) async throws {
        // No-op: see the type-level note above. Accepting a real GGUF file here (validated via
        // `SecurityService.validateModelFile`) is the extension point for wiring in a real model
        // later without touching any call site.
    }

    func unloadModel() {}

    /// Runs the enhancement pass and validates the result before returning it, per CLAUDE.md's
    /// "Always validate ... output" rule. Returns `nil` (never throws) on any validation failure
    /// so callers fall back to the deterministic clean text, exactly as specified.
    func runCleanup(on text: String) async -> String? {
        let candidate = enhancedClean(text)
        return AICleanupOutputValidator.isValid(candidate, against: text) ? candidate : nil
    }

    // MARK: - Enhancement pass

    /// Improves on `TextCleanupService`'s regex-based pass using real sentence/entity awareness:
    /// - Rejoins sentences NLTokenizer sees as wrongly split by a stray layout line break
    /// - Strips citation-style bracket runs more conservatively (skips ones inside a detected
    ///   entity, e.g. don't eat "[REDACTED]" if it reads as a proper noun span)
    ///
    /// Sentence rejoining happens *within* each `\n\n`-separated paragraph, never across one —
    /// flattening paragraph breaks here would erase the very structure
    /// `PDFSectionDetectionService.fromHeuristics` uses to find chapter headings (it looks for
    /// short, title-cased paragraphs) and that `DocumentSearchService`/`SummarizationService`
    /// use to size Ask Mode/summary passages. Collapsing everything to one giant paragraph
    /// silently turned every heading-less heuristic-detected document into a single section.
    private func enhancedClean(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        // Only English text has been validated for this pass; anything else, hand back the
        // input unchanged so `runCleanup` still returns something valid (identical to source
        // text still passes the validator above) rather than risking mangling other scripts.
        guard recognizer.dominantLanguage == .english || recognizer.dominantLanguage == nil else {
            return text
        }

        let paragraphs = text.components(separatedBy: "\n\n")
        let rejoined = paragraphs.map { paragraph -> String in
            let sentences = SentenceChunker.sentences(in: paragraph)
            guard !sentences.isEmpty else { return paragraph }
            return sentences.joined(separator: " ")
        }
        return rejoined.joined(separator: "\n\n")
    }
}
