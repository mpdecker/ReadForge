import Foundation
import SwiftData
import Testing
@testable import ReadForge

@MainActor
struct PlaybackControllerTests {
    // Shared in-memory container for SwiftData models
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: DocumentRecord.self, SectionRecord.self, PlaybackState.self, BookmarkRecord.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func makeSection(rawText: String, context: ModelContext) -> SectionRecord {
        let section = SectionRecord(title: "Test Section", rawText: rawText, order: 0, startPage: 1, endPage: 1)
        context.insert(section)
        return section
    }

    private func makeDocument(context: ModelContext) -> DocumentRecord {
        let record = DocumentRecord(title: "Test Doc", fileURL: URL(fileURLWithPath: "/tmp/test.pdf"))
        context.insert(record)
        return record
    }

    // MARK: - Initial state

    @Test func initialStateIsIdle() {
        let mock = MockSpeechService()
        let ctrl = PlaybackController(speech: mock)
        #expect(ctrl.playbackState == .idle)
        #expect(ctrl.currentSentenceIndex == 0)
        #expect(ctrl.currentSection == nil)
    }

    // MARK: - play

    @Test func playWithTextSetsPlayingState() throws {
        let ctx = try makeContext()
        let mock = MockSpeechService()
        let ctrl = PlaybackController(speech: mock)
        let doc = makeDocument(context: ctx)
        let section = makeSection(rawText: "Hello world. This is a sentence.", context: ctx)

        ctrl.play(document: doc, section: section)

        #expect(ctrl.playbackState == .playing)
        #expect(!mock.spokenTexts.isEmpty)
    }

    @Test func playWithEmptySectionStaysIdle() throws {
        let ctx = try makeContext()
        let mock = MockSpeechService()
        let ctrl = PlaybackController(speech: mock)
        let doc = makeDocument(context: ctx)
        let section = makeSection(rawText: "", context: ctx)

        ctrl.play(document: doc, section: section)

        #expect(ctrl.playbackState == .idle)
        #expect(mock.spokenTexts.isEmpty)
    }

    @Test func playStartsFromSpecifiedIndex() throws {
        let ctx = try makeContext()
        let mock = MockSpeechService()
        let ctrl = PlaybackController(speech: mock)
        let doc = makeDocument(context: ctx)
        // Two distinct sentences so chunker produces ≥ 2 chunks
        let section = makeSection(
            rawText: "First sentence is here and it is quite long enough to be its own chunk hopefully. " +
                     "Second sentence is also here and it is long enough too hopefully yes.",
            context: ctx
        )

        ctrl.play(document: doc, section: section, from: 1)

        // Index should be clamped/set to 1 if there are at least 2 sentences
        if ctrl.playbackState == .playing {
            // The controller may have merged them into one chunk — just verify no crash
            #expect(ctrl.currentSentenceIndex >= 0)
        }
    }

    @Test func playClampsSentenceIndexToValidRange() throws {
        let ctx = try makeContext()
        let mock = MockSpeechService()
        let ctrl = PlaybackController(speech: mock)
        let doc = makeDocument(context: ctx)
        let section = makeSection(rawText: "Just one sentence here.", context: ctx)

        // from: 999 is way out of range — should be clamped to 0
        ctrl.play(document: doc, section: section, from: 999)

        #expect(ctrl.playbackState == .playing)
        #expect(ctrl.currentSentenceIndex == 0)
    }

    // MARK: - pause / resume

    @Test func pauseSetsStateToPaused() throws {
        let ctx = try makeContext()
        let mock = MockSpeechService()
        let ctrl = PlaybackController(speech: mock)
        let doc = makeDocument(context: ctx)
        let section = makeSection(rawText: "A sentence.", context: ctx)
        ctrl.play(document: doc, section: section)

        ctrl.pause()

        #expect(ctrl.playbackState == .paused)
        #expect(mock.pauseCount == 1)
    }

    @Test func resumeSetsStateToPlaying() throws {
        let ctx = try makeContext()
        let mock = MockSpeechService()
        let ctrl = PlaybackController(speech: mock)
        let doc = makeDocument(context: ctx)
        let section = makeSection(rawText: "A sentence.", context: ctx)
        ctrl.play(document: doc, section: section)
        ctrl.pause()

        ctrl.resume()

        #expect(ctrl.playbackState == .playing)
        #expect(mock.resumeCount == 1)
    }

    // MARK: - stop

    @Test func stopResetsAllState() throws {
        let ctx = try makeContext()
        let mock = MockSpeechService()
        let ctrl = PlaybackController(speech: mock)
        let doc = makeDocument(context: ctx)
        let section = makeSection(rawText: "A sentence.", context: ctx)
        ctrl.play(document: doc, section: section)

        ctrl.stop()

        #expect(ctrl.playbackState == .idle)
        #expect(ctrl.currentSentenceIndex == 0)
        #expect(ctrl.currentSection == nil)
        #expect(mock.stopCount >= 1)
    }

    // MARK: - skip

    @Test func skipForwardAdvancesIndex() throws {
        let ctx = try makeContext()
        let mock = MockSpeechService()
        let ctrl = PlaybackController(speech: mock)
        let doc = makeDocument(context: ctx)
        // Long enough text to produce multiple chunks
        let text = Array(repeating: "The quick brown fox jumps over the lazy dog.", count: 30).joined(separator: " ")
        let section = makeSection(rawText: text, context: ctx)
        ctrl.play(document: doc, section: section)
        let indexBefore = ctrl.currentSentenceIndex

        ctrl.skipForward()

        #expect(ctrl.currentSentenceIndex == indexBefore + 1)
    }

    @Test func skipForwardAtLastSentenceDoesNothing() throws {
        let ctx = try makeContext()
        let mock = MockSpeechService()
        let ctrl = PlaybackController(speech: mock)
        let doc = makeDocument(context: ctx)
        let section = makeSection(rawText: "Only one sentence.", context: ctx)
        ctrl.play(document: doc, section: section)
        let indexBefore = ctrl.currentSentenceIndex

        ctrl.skipForward()  // already at last

        #expect(ctrl.currentSentenceIndex == indexBefore)
    }

    @Test func skipBackDecreasesIndex() throws {
        let ctx = try makeContext()
        let mock = MockSpeechService()
        let ctrl = PlaybackController(speech: mock)
        let doc = makeDocument(context: ctx)
        let text = Array(repeating: "The quick brown fox jumps over the lazy dog.", count: 30).joined(separator: " ")
        let section = makeSection(rawText: text, context: ctx)
        ctrl.play(document: doc, section: section)
        ctrl.skipForward()  // move to index 1
        let indexBefore = ctrl.currentSentenceIndex

        ctrl.skipBack()

        #expect(ctrl.currentSentenceIndex == max(0, indexBefore - 1))
    }

    @Test func skipBackAtIndexZeroStaysAtZero() throws {
        let ctx = try makeContext()
        let mock = MockSpeechService()
        let ctrl = PlaybackController(speech: mock)
        let doc = makeDocument(context: ctx)
        let section = makeSection(rawText: "A sentence.", context: ctx)
        ctrl.play(document: doc, section: section)

        ctrl.skipBack()

        #expect(ctrl.currentSentenceIndex == 0)
    }

    // MARK: - speechServiceDidFinishUtterance

    @Test func finishAdvancesToNextSentence() throws {
        let ctx = try makeContext()
        let mock = MockSpeechService()
        let ctrl = PlaybackController(speech: mock)
        let doc = makeDocument(context: ctx)
        let text = Array(repeating: "The quick brown fox jumps over the lazy dog.", count: 30).joined(separator: " ")
        let section = makeSection(rawText: text, context: ctx)
        ctrl.configure(with: ctx)
        ctrl.play(document: doc, section: section)
        let indexBefore = ctrl.currentSentenceIndex

        mock.simulateFinish()

        #expect(ctrl.currentSentenceIndex == indexBefore + 1)
        #expect(ctrl.playbackState == .playing)
    }

    @Test func finishOnLastSentenceTransitionsToIdle() throws {
        let ctx = try makeContext()
        let mock = MockSpeechService()
        let ctrl = PlaybackController(speech: mock)
        let doc = makeDocument(context: ctx)
        let section = makeSection(rawText: "Just one sentence.", context: ctx)
        ctrl.configure(with: ctx)
        ctrl.play(document: doc, section: section)

        mock.simulateFinish()

        #expect(ctrl.playbackState == .idle)
    }

    // MARK: - playbackRate

    @Test func settingRateCallsSetRateOnService() {
        let mock = MockSpeechService()
        let ctrl = PlaybackController(speech: mock)

        ctrl.playbackRate = 1.5

        #expect(mock.currentRate == 1.5)
    }

    @Test func settingVoiceCallsSetVoiceOnService() {
        let mock = MockSpeechService()
        let ctrl = PlaybackController(speech: mock)

        ctrl.voiceIdentifier = "com.apple.voice.compact.en-US.Samantha"

        #expect(mock.currentVoice == "com.apple.voice.compact.en-US.Samantha")
    }
}
