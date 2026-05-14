import Foundation
import AVFoundation
import MediaPlayer
import SwiftData
import Combine

@Observable
@MainActor
final class PlaybackController: SpeechServiceDelegate {
    enum State: Equatable { case idle, playing, paused }

    private(set) var playbackState: State = .idle
    private(set) var currentSentenceIndex = 0
    private(set) var currentSection: SectionRecord?

    var playbackRate: Float = 1.0 { didSet { speech.setRate(playbackRate) } }
    var voiceIdentifier: String? { didSet { speech.setVoice(voiceIdentifier) } }

    private let speech: SpeechServiceProtocol
    private let chunker = SentenceChunker()
    private var sentences: [String] = []
    private var modelContext: ModelContext?
    private var document: DocumentRecord?
    private var didRegisterRemoteCommands = false

    init(speech: SpeechServiceProtocol = NativeSpeechService()) {
        self.speech = speech
        self.speech.delegate = self
    }

    func configure(with context: ModelContext) {
        modelContext = context
    }

    func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            ReadForgeLogger.error(category: "Playback", message: "AVAudioSession configuration failed", error: error)
        }
        setupRemoteCommandsOnce()
    }

    func play(document: DocumentRecord, section: SectionRecord, from sentenceIndex: Int = 0) {
        self.document = document
        currentSection = section
        sentences = chunker.chunk(section.cleanText ?? section.rawText)

        guard !sentences.isEmpty else {
            playbackState = .idle
            return
        }

        // Clamp index in case text changed length since progress was saved
        currentSentenceIndex = min(max(sentenceIndex, 0), sentences.count - 1)
        playbackState = .playing
        speakCurrentSentence()
        updateNowPlaying()
    }

    func pause() {
        speech.pause()
        playbackState = .paused
        updateNowPlaying()
    }

    func resume() {
        speech.resume()
        playbackState = .playing
        updateNowPlaying()
    }

    func stop() {
        speech.stop()
        playbackState = .idle
        sentences = []
        currentSection = nil
        currentSentenceIndex = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func skipForward() {
        let next = currentSentenceIndex + 1
        guard next < sentences.count else { return }
        speech.stop()
        currentSentenceIndex = next
        speakCurrentSentence()
    }

    func skipBack() {
        speech.stop()
        currentSentenceIndex = max(0, currentSentenceIndex - 1)
        speakCurrentSentence()
    }

    // MARK: - SpeechServiceDelegate
    // AVSpeechSynthesizerDelegate is @MainActor — no extra dispatch needed.

    func speechServiceDidFinishUtterance() {
        saveProgress()
        let next = currentSentenceIndex + 1
        if next < sentences.count {
            currentSentenceIndex = next
            speakCurrentSentence()
            updateNowPlaying()
        } else {
            playbackState = .idle
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }

    func speechServiceWillSpeakRange(_ range: NSRange, in utterance: String) {}

    // MARK: - Private

    private func speakCurrentSentence() {
        guard currentSentenceIndex < sentences.count else { return }
        speech.speak(sentences[currentSentenceIndex])
    }

    private func saveProgress() {
        guard let doc = document, let section = currentSection, let ctx = modelContext else { return }
        StorageService.updateProgress(
            document: doc,
            sectionId: section.id,
            sentenceIndex: currentSentenceIndex,
            characterOffset: 0,
            context: ctx
        )
    }

    // Duration in seconds estimated from word count at current playback rate.
    private func updateNowPlaying() {
        guard let doc = document, let section = currentSection else { return }

        let wpm = Double(playbackRate) * 160.0
        let wordCounts = sentences.map { $0.split(separator: " ").count }
        let totalWords = wordCounts.reduce(0, +)
        let elapsedWords = wordCounts.prefix(currentSentenceIndex).reduce(0, +)
        let totalSeconds = Double(totalWords) / wpm * 60.0
        let elapsedSeconds = Double(elapsedWords) / wpm * 60.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: section.title,
            MPMediaItemPropertyAlbumTitle: doc.title,
            MPNowPlayingInfoPropertyPlaybackRate: playbackState == .playing ? Double(playbackRate) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPMediaItemPropertyPlaybackDuration: totalSeconds,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsedSeconds
        ]
    }

    private func setupRemoteCommandsOnce() {
        guard !didRegisterRemoteCommands else { return }
        didRegisterRemoteCommands = true

        let rc = MPRemoteCommandCenter.shared()
        rc.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        rc.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        rc.skipForwardCommand.preferredIntervals = [15]
        rc.skipForwardCommand.addTarget { [weak self] _ in self?.skipForward(); return .success }
        rc.skipBackwardCommand.preferredIntervals = [15]
        rc.skipBackwardCommand.addTarget { [weak self] _ in self?.skipBack(); return .success }
        rc.nextTrackCommand.isEnabled = false
        rc.previousTrackCommand.isEnabled = false
    }
}
