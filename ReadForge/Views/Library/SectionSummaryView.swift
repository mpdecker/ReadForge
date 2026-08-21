import SwiftUI
import Combine

/// Wraps `NativeSpeechService` for a single one-off utterance (the summary text) — the summary
/// view doesn't need `PlaybackController`'s sentence-by-sentence progress tracking, just
/// start/stop and a state to drive the toolbar button.
@MainActor
private final class SummarySpeaker: NSObject, ObservableObject, SpeechServiceDelegate {
    @Published var isSpeaking = false
    private let speech: SpeechServiceProtocol

    override init() {
        speech = NativeSpeechService()
        super.init()
        speech.delegate = self
    }

    func toggle(_ text: String) {
        if isSpeaking {
            speech.stop()
            isSpeaking = false
        } else {
            speech.speak(text)
            isSpeaking = true
        }
    }

    func stop() {
        speech.stop()
        isSpeaking = false
    }

    func speechServiceDidFinishUtterance() {
        isSpeaking = false
    }

    func speechServiceWillSpeakRange(_ range: NSRange, in utterance: String) {}
}

/// Summary of a section (CLAUDE.md v1.5: "summaries") — a real generative summary via
/// `TieredSummarizationService` on devices where Apple's on-device Foundation Model is
/// available, falling back to `SummarizationService`'s extractive (ranked source sentences)
/// approach everywhere else.
struct SectionSummaryView: View {
    let section: SectionRecord
    @State private var summary: String?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @StateObject private var speaker = SummarySpeaker()

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Summarizing…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let summary {
                ScrollView {
                    Text(summary)
                        .font(.body)
                        .lineSpacing(4)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "text.redaction")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(errorMessage ?? "Couldn't summarize this section.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let summary {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        speaker.toggle(summary)
                    } label: {
                        Label(
                            speaker.isSpeaking ? "Stop" : "Read Aloud",
                            systemImage: speaker.isSpeaking ? "stop.fill" : "play.fill"
                        )
                    }
                }
            }
        }
        .task { await generateSummary() }
        .onDisappear { speaker.stop() }
    }

    private func generateSummary() async {
        isLoading = true
        let text = section.cleanText ?? section.rawText
        let result: Result<String, Error> = await Task.detached(priority: .userInitiated) {
            do {
                return .success(try await TieredSummarizationService().summarize(text))
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let text): summary = text
        case .failure(let error): errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
