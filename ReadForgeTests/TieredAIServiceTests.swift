import Testing
@testable import ReadForge

/// Exercises the tiered AI services' fallback path — the one guaranteed to run everywhere,
/// since `SystemLanguageModel.default.availability` isn't `.available` in the test/CI
/// environment (no Apple-Intelligence-eligible hardware backing the simulator/test host). The
/// availability check itself, and the `FoundationModelTextCleanupService`/
/// `FoundationModelSummarizationService` code paths, need real device/Apple-Intelligence-enabled
/// verification this session can't perform — see those types' doc comments.
struct TieredAIServiceTests {
    @Test func tieredCleanupProducesAResult() async throws {
        let service = TieredTextCleanupService()
        let result = await service.runCleanup(on: "This is a perfectly ordinary sentence for testing purposes here.")
        #expect(result != nil)
    }

    @Test func tieredCleanupReportsAModelName() {
        let service = TieredTextCleanupService()
        #expect(service.modelName != nil)
    }

    @Test func tieredSummarizationProducesAResult() async throws {
        let sentences = (1...20).map { "This is sentence number \($0) with some extra words to pad it out nicely." }
        let text = sentences.joined(separator: " ")

        let result = try await TieredSummarizationService().summarize(text, maxSentences: 5)
        #expect(!result.isEmpty)
    }

    @available(iOS 26.0, *)
    @Test func foundationModelServicesReportAvailabilityWithoutCrashing() {
        // In this environment `SystemLanguageModel.default.availability` should be
        // `.unavailable` (no Apple-Intelligence-eligible hardware backs the test host), but the
        // point of this test is just that checking it, and every service built on top of it,
        // never crashes regardless of which way it comes back.
        _ = FoundationModelTextCleanupService.isSystemModelAvailable
        _ = FoundationModelSummarizationService.isSystemModelAvailable
        _ = FoundationModelAnswerService.isSystemModelAvailable
    }
}
