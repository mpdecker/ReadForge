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

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        delegate?.speechServiceDidFinishUtterance()
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        delegate?.speechServiceWillSpeakRange(characterRange, in: utterance.speechString)
    }
}
