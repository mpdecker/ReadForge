import Foundation
import AVFoundation

protocol SpeechServiceProtocol: AnyObject {
    var delegate: SpeechServiceDelegate? { get set }
    func speak(_ text: String)
    func pause()
    func resume()
    func stop()
    func setRate(_ rate: Float)
    func setVoice(_ voiceIdentifier: String?)
    var availableVoices: [AVSpeechSynthesisVoice] { get }
}

protocol SpeechServiceDelegate: AnyObject {
    func speechServiceDidFinishUtterance()
    func speechServiceWillSpeakRange(_ range: NSRange, in utterance: String)
}

final class NativeSpeechService: NSObject, SpeechServiceProtocol, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    private var voiceIdentifier: String?
    private var currentText: String = ""

    weak var delegate: SpeechServiceDelegate?

    var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        currentText = text
        // `AVSpeechSynthesizer.speak(_:)` enqueues rather than interrupts if the synthesizer is
        // already speaking — every current call site in `PlaybackController` stops first, so
        // this was never actually triggered, but the method itself provided no protection: any
        // future/alternate caller that forgot to stop first would silently queue utterances that
        // played back-to-back unexpectedly instead of replacing what was playing.
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.voice = voiceIdentifier.flatMap { AVSpeechSynthesisVoice(identifier: $0) }
            ?? AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    func pause() { synthesizer.pauseSpeaking(at: .word) }
    func resume() { synthesizer.continueSpeaking() }
    func stop() { synthesizer.stopSpeaking(at: .immediate) }
    func setRate(_ rate: Float) { self.rate = rate }
    func setVoice(_ voiceIdentifier: String?) { self.voiceIdentifier = voiceIdentifier }

    // AVSpeechSynthesizerDelegate callbacks aren't documented as guaranteed to arrive on the
    // main thread, and `delegate` (`PlaybackController`) is `@MainActor` — it mutates
    // `@Observable` playback state and saves to a SwiftData `ModelContext` directly from
    // `speechServiceDidFinishUtterance()`. Hopping explicitly here mirrors the same defensive
    // pattern `PlaybackController` already uses for its `AVAudioPlayerDelegate` conformance
    // (`nonisolated` + `Task { @MainActor in ... }`) rather than assuming these two delegate
    // APIs behave differently.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.delegate?.speechServiceDidFinishUtterance()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.delegate?.speechServiceWillSpeakRange(characterRange, in: utterance.speechString)
        }
    }
}
