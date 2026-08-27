import Foundation

/// What `SectionSummaryView` actually calls — prefers a real generative summary
/// (`FoundationModelSummarizationService`, iOS 26+ on eligible hardware) and falls back to the
/// extractive `SummarizationService` (TextRank-style sentence ranking) everywhere else. Same
/// progressive-enhancement shape as `TieredTextCleanupService`: no deployment-target change,
/// every device gets a working summary either way.
struct TieredSummarizationService {
    func summarize(_ text: String, maxSentences: Int = 5) async throws -> String {
        if #available(iOS 26.0, *), FoundationModelSummarizationService.isSystemModelAvailable {
            if let result = await FoundationModelSummarizationService().summarize(text, maxSentences: maxSentences) {
                return result
            }
            // Model available but this call failed validation or threw — fall through to the
            // extractive summarizer rather than surfacing an error for something recoverable.
        }
        return try SummarizationService().summarize(text, maxSentences: maxSentences)
    }
}
