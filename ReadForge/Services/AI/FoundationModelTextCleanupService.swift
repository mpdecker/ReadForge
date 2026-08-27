import Foundation
import FoundationModels

/// Real generative text cleanup using Apple's on-device Foundation Model (CLAUDE.md Phase 9:
/// "Local LLM cleanup"), using the exact prompt CLAUDE.md's "LLM Cleanup Prompt" section
/// specifies. This is genuinely a large language model running the actual cleanup task — not a
/// heuristic standing in for one — via the `FoundationModels` framework Apple ships on-device
/// starting iOS 26. It requires no bundled model weights (Apple ships and updates the model as
/// part of the OS) and never leaves the device, matching CLAUDE.md's privacy rules exactly.
///
/// Availability is real hardware/OS/settings-dependent, not just an iOS-version check — even on
/// iOS 26+, `SystemLanguageModel.default.availability` can report `.unavailable` for a device
/// that isn't Apple-Intelligence-eligible, has it turned off in Settings, or hasn't finished
/// downloading the on-device asset yet. `isSystemModelAvailable` checks the real thing, and
/// `TieredTextCleanupService` uses that check to fall back to `TextCleanupAIService`'s
/// NaturalLanguage-based pass whenever this isn't actually usable.
@available(iOS 26.0, *)
struct FoundationModelTextCleanupService: AIModelManaging {
    static var isSystemModelAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    var isLoaded: Bool { true }
    var modelName: String? { "Apple On-Device Foundation Model" }

    func loadModel(at url: URL) async throws {
        // No-op: there's no model file to load — Apple ships and manages this model as part of
        // the OS, downloaded and updated outside the app entirely.
    }

    func unloadModel() {}

    func runCleanup(on text: String) async -> String? {
        guard Self.isSystemModelAvailable else { return nil }
        // A safety margin against the model's context window, not the primary size control —
        // `PDFSectionDetectionService` already caps sections at ~3,000 words, and cleanup runs
        // per-page (smaller still), so this should essentially never trigger in practice; if it
        // ever does, falling back to the deterministic/NLP pass is the right call anyway.
        guard text.count < 12_000 else { return nil }

        let session = LanguageModelSession(instructions: Self.instructions)
        do {
            let response = try await session.respond(to: text)
            let candidate = response.content
            return AICleanupOutputValidator.isValid(candidate, against: text) ? candidate : nil
        } catch {
            ReadForgeLogger.error(category: "AI", message: "Foundation Model cleanup failed", error: error)
            return nil
        }
    }

    // Verbatim from CLAUDE.md's "LLM Cleanup Prompt" section.
    private static let instructions = """
    You are preparing PDF text for spoken narration.
    Remove layout artifacts, headers, footers, broken line wraps, and citation clutter.
    Preserve all meaning. Do not summarize. Return only the cleaned text.
    """
}
