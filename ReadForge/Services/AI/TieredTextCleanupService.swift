import Foundation

/// The `AIModelManaging` conformance actually registered in `ServiceContainer` — prefers a real
/// generative model (`FoundationModelTextCleanupService`, iOS 26+ on eligible hardware with
/// Apple Intelligence enabled) and falls back to `TextCleanupAIService`'s NaturalLanguage-based
/// pass everywhere else. This is genuine progressive enhancement based on real device
/// capability, not a version-gate that drops support for older devices — ReadForge's minimum
/// deployment target stays iOS 17, and every device gets a working cleanup pass either way.
struct TieredTextCleanupService: AIModelManaging {
    var isLoaded: Bool { true }

    var modelName: String? {
        if #available(iOS 26.0, *), FoundationModelTextCleanupService.isSystemModelAvailable {
            return FoundationModelTextCleanupService().modelName
        }
        return TextCleanupAIService().modelName
    }

    func loadModel(at url: URL) async throws {}
    func unloadModel() {}

    func runCleanup(on text: String) async -> String? {
        if #available(iOS 26.0, *), FoundationModelTextCleanupService.isSystemModelAvailable {
            if let result = await FoundationModelTextCleanupService().runCleanup(on: text) {
                return result
            }
            // The generative path is available but this particular call failed validation or
            // threw — fall through to the deterministic pass rather than giving up entirely,
            // same "fall back on failure" rule CLAUDE.md specifies for the LLM path itself.
        }
        return await TextCleanupAIService().runCleanup(on: text)
    }
}
