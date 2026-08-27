import Foundation
import AVFoundation
import MediaPlayer
import SwiftData
import Combine

@Observable
@MainActor
final class PlaybackController: NSObject, SpeechServiceDelegate, AVAudioPlayerDelegate {
    enum State: Equatable { case idle, playing, paused }

    private(set) var playbackState: State = .idle
    private(set) var currentSentenceIndex = 0
    private(set) var currentSection: SectionRecord?

    /// Set when audio session activation fails — previously this only got logged, so tapping
    /// Play produced total silence with no indication anything had gone wrong.
    private(set) var lastErrorMessage: String?

    /// The word/range about to be spoken, within the current sentence. For live TTS this comes
    /// straight from `speechServiceWillSpeakRange` (the hook already existed but was an empty
    /// no-op before) — this path is confirmed working. For cached playback, `AVAudioPlayer` has
    /// no per-word callback of its own — `wordHighlightTimer` polls `cachedPlayer.currentTime`
    /// against real per-word timings captured when the clip was cached
    /// (`AudioCacheService.WordTiming`, via `AVSpeechSynthesizer`'s marker callback) and updates
    /// this the same way, when timings exist. See `AudioCacheService.WordTiming`'s doc comment:
    /// every voice available in this session's test environment produced zero markers, verified
    /// directly, so on a device with only standard-quality voices this currently stays `nil` for
    /// cached playback in practice — not a bug, the honest "nothing to show" fallback, but worth
    /// confirming on a device with an Enhanced/Premium voice before calling this path proven.
    private(set) var currentWordRange: NSRange?
    private var cachedWordTimings: [AudioCacheService.WordTiming]?
    private var wordHighlightTimer: Timer?

    var playbackRate: Float = 1.0 { didSet { speech.setRate(playbackRate) } }
    var voiceIdentifier: String? { didSet { speech.setVoice(voiceIdentifier) } }

    private let speech: SpeechServiceProtocol
    private let chunker = SentenceChunker()
    /// Consulted before every sentence: if "Download for offline" (see `DocumentDetailView`)
    /// already rendered this exact sentence — same document/section/voice/speed/text — it's
    /// played straight from disk via `cachedPlayer` instead of running live TTS again. Previously
    /// this cache was write-only: populated by the Download action but never read back by
    /// playback, so it did nothing but use disk space.
    private let audioCache = AudioCacheService.shared
    private var cachedPlayer: AVAudioPlayer?
    private var sentences: [String] = []
    private var modelContext: ModelContext?
    private var document: DocumentRecord?
    private var didRegisterRemoteCommands = false
    private var didRegisterInterruptionHandling = false
    /// Distinguishes "paused because an interruption began" from "the user tapped Pause" — an
    /// interruption ending with `.shouldResume` should only resume playback in the former case.
    private var pausedByInterruption = false

    init(speech: SpeechServiceProtocol = NativeSpeechService()) {
        self.speech = speech
        super.init()
        self.speech.delegate = self
    }

    func configure(with context: ModelContext) {
        modelContext = context
    }

    /// Reads the user's default voice/speed from Settings (`SettingsView`'s
    /// `defaultVoiceIdentifier`/`defaultPlaybackRate` `@AppStorage` keys).
    ///
    /// This didn't exist before — nothing ever seeded `voiceIdentifier`/`playbackRate` from
    /// those keys, so the Settings voice picker had no effect on playback at all (every session
    /// silently used the system default voice), and `playbackRate` only ever reflected whatever
    /// the in-player Speed picker was set to that session. It also meant "Download for offline"
    /// (`DocumentDetailView.precacheSection`, which reads these same keys to build its cache
    /// key) and live playback almost never agreed on a cache key whenever the user had picked a
    /// non-default voice/speed, so the cache silently never hit for those users. Both call
    /// sites now go through this one shared reader instead of each re-deriving it independently.
    static func defaultVoiceAndRate() -> (voiceId: String?, rate: Float) {
        let storedVoice = UserDefaults.standard.string(forKey: "defaultVoiceIdentifier")
        let voiceId = (storedVoice?.isEmpty == false) ? storedVoice : nil
        let storedRate = UserDefaults.standard.double(forKey: "defaultPlaybackRate")
        let rate = Float(storedRate == 0 ? 1.0 : storedRate)
        return (voiceId, rate)
    }

    func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            lastErrorMessage = nil
        } catch {
            ReadForgeLogger.error(category: "Playback", message: "AVAudioSession configuration failed", error: error)
            lastErrorMessage = "Couldn't start audio playback: \(error.localizedDescription)"
        }
        setupRemoteCommandsOnce()
        setupInterruptionHandlingOnce()
    }

    func play(document: DocumentRecord, section: SectionRecord, from sentenceIndex: Int = 0) {
        // Without this, calling play() while a previous section/document's audio is still
        // running (cached-file playback or live TTS) left that old audio playing underneath
        // the new one instead of replacing it — two overlapping streams.
        stopCurrentUtterance()

        self.document = document
        currentSection = section
        sentences = chunker.chunk(section.cleanText ?? section.rawText)

        guard !sentences.isEmpty else {
            playbackState = .idle
            lastErrorMessage = "This chapter has no readable text to play."
            return
        }

        // Clamp index in case text changed length since progress was saved
        currentSentenceIndex = min(max(sentenceIndex, 0), sentences.count - 1)
        playbackState = .playing
        lastErrorMessage = nil
        speakCurrentSentence()
        updateNowPlaying()
    }

    func pause() {
        pausedByInterruption = false
        if let cachedPlayer {
            cachedPlayer.pause()
        } else {
            speech.pause()
        }
        playbackState = .paused
        updateNowPlaying()
    }

    func resume() {
        pausedByInterruption = false
        if let cachedPlayer {
            cachedPlayer.play()
        } else {
            speech.resume()
        }
        playbackState = .playing
        updateNowPlaying()
    }

    func stop() {
        speech.stop()
        cachedPlayer?.stop()
        cachedPlayer = nil
        stopWordHighlightTimer()
        playbackState = .idle
        sentences = []
        currentSection = nil
        currentSentenceIndex = 0
        currentWordRange = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func dismissError() {
        lastErrorMessage = nil
    }

    func skipForward() {
        let next = currentSentenceIndex + 1
        guard next < sentences.count else { return }
        stopCurrentUtterance()
        currentSentenceIndex = next
        speakCurrentSentence()
    }

    func skipBack() {
        stopCurrentUtterance()
        currentSentenceIndex = max(0, currentSentenceIndex - 1)
        speakCurrentSentence()
    }

    // MARK: - SpeechServiceDelegate
    // AVSpeechSynthesizerDelegate is @MainActor — no extra dispatch needed.

    func speechServiceDidFinishUtterance() {
        advanceAfterFinishingCurrentUtterance()
    }

    func speechServiceWillSpeakRange(_ range: NSRange, in utterance: String) {
        currentWordRange = range
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            // Ignore a stale finish callback from a player that's no longer the active one
            // (e.g. `stop()`/`skipForward()` already moved on and released it), and ignore one
            // that raced a `pause()` — `AVAudioPlayer.pause()` doesn't cancel an
            // already-in-flight "did finish" notification if the player reached the end of the
            // file at nearly the same moment, so without this check a pause landing right at
            // the tail of a cached sentence could still silently advance to and start speaking
            // the next one while the UI reads "Paused".
            guard player === self.cachedPlayer, self.playbackState == .playing else { return }
            self.cachedPlayer = nil
            self.advanceAfterFinishingCurrentUtterance()
        }
    }

    // MARK: - Private

    /// Shared by both playback sources' "finished this sentence" path — live TTS
    /// (`speechServiceDidFinishUtterance`) and cached-audio playback
    /// (`audioPlayerDidFinishPlaying`) — so progress saving and advancing to the next sentence
    /// behave identically regardless of which one actually produced the audio.
    private func advanceAfterFinishingCurrentUtterance() {
        saveProgress()
        let next = currentSentenceIndex + 1
        if next < sentences.count {
            currentSentenceIndex = next
            speakCurrentSentence()
            updateNowPlaying()
        } else {
            // Without this, finishing the last cached sentence of a section left
            // `wordHighlightTimer` running indefinitely — `speakCurrentSentence()` (which
            // otherwise stops it) is never called again once there's no next sentence, so the
            // timer just kept firing every 80ms until the next `play()`/`stop()`.
            stopWordHighlightTimer()
            playbackState = .idle
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }

    private func stopCurrentUtterance() {
        speech.stop()
        cachedPlayer?.stop()
        cachedPlayer = nil
        stopWordHighlightTimer()
    }

    private func speakCurrentSentence() {
        guard currentSentenceIndex < sentences.count else { return }
        let text = sentences[currentSentenceIndex]
        // Clear any highlight/timer from the previous sentence up front — unconditionally,
        // regardless of which path (live or cached) this sentence ends up taking. Without this,
        // a sentence that falls through to live `speech.speak(text)` right after a cached one
        // would leave the previous cached sentence's highlight timer running forever (it'd be
        // harmless — `updateHighlightFromCachedPlayer` no-ops once `cachedPlayer` is nil — but
        // never invalidated).
        currentWordRange = nil
        stopWordHighlightTimer()

        if let document, let currentSection {
            let key = audioCache.cacheKey(
                documentId: document.id, sectionId: currentSection.id,
                voiceId: voiceIdentifier, rate: playbackRate, text: text
            )
            if let cachedURL = audioCache.cachedFileURLSync(forKey: key),
               let player = try? AVAudioPlayer(contentsOf: cachedURL) {
                player.delegate = self
                cachedPlayer = player
                cachedWordTimings = audioCache.wordTimingsSync(forKey: key)
                player.play()
                startWordHighlightTimerIfNeeded()
                return
            }
        }

        speech.speak(text)
    }

    /// Polls `cachedPlayer.currentTime` against `cachedWordTimings` — the only way to highlight
    /// words during cached playback, since `AVAudioPlayer` has no per-word callback the way
    /// `AVSpeechSynthesizerDelegate.speechServiceWillSpeakRange` provides for live TTS. No-ops
    /// (and clears any stale timer) when this clip has no timings to show.
    private func startWordHighlightTimerIfNeeded() {
        stopWordHighlightTimer()
        guard cachedWordTimings?.isEmpty == false else { return }

        // `Timer.scheduledTimer` registers in the default run-loop mode only, which stops
        // firing while the main run loop is in `.tracking`/`.eventTracking` mode — e.g. while
        // the user drags the sentence view's ScrollView. Without `.common`, the highlight would
        // visibly freeze mid-scroll and jump forward the moment the gesture ends.
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateHighlightFromCachedPlayer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        wordHighlightTimer = timer
    }

    private func stopWordHighlightTimer() {
        wordHighlightTimer?.invalidate()
        wordHighlightTimer = nil
        cachedWordTimings = nil
    }

    private func updateHighlightFromCachedPlayer() {
        guard let cachedPlayer, let timings = cachedWordTimings else { return }
        let elapsed = cachedPlayer.currentTime
        // The last timing whose start time has already passed — timings are captured in the
        // order markers fire during synthesis, which is monotonically increasing, so this is a
        // simple "most recent one reached" lookup rather than needing a binary search.
        guard let current = timings.last(where: { $0.time <= elapsed }) else { return }
        currentWordRange = current.range
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

    /// Without this, a phone call or another app taking over audio would silently stop
    /// narration mid-sentence with no way to resume — the playback state would still say
    /// "playing" while nothing was actually audible.
    private func setupInterruptionHandlingOnce() {
        guard !didRegisterInterruptionHandling else { return }
        didRegisterInterruptionHandling = true

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue)
            else { return }

            switch type {
            case .began:
                if self.playbackState == .playing {
                    self.pause()
                    self.pausedByInterruption = true
                }
            case .ended:
                // Only resume if THIS interruption is what paused it — otherwise an unrelated
                // interruption ending while the user is deliberately paused (e.g. reading in
                // silence) would restart narration against their explicit Pause action.
                let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt
                let options = optionsValue.map(AVAudioSession.InterruptionOptions.init(rawValue:))
                if self.pausedByInterruption, options?.contains(.shouldResume) == true {
                    // The interruption (a call, Siri, another app's audio) may have deactivated
                    // the shared session entirely — `resume()` only tells `speech`/`cachedPlayer`
                    // to keep going, it never reactivates the session itself. Without this,
                    // `playbackState` could flip back to `.playing` with nothing actually
                    // audible.
                    try? AVAudioSession.sharedInstance().setActive(true)
                    self.resume()
                }
                self.pausedByInterruption = false
            @unknown default:
                break
            }
        }
    }
}
