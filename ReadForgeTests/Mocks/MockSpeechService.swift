import AVFoundation
@testable import ReadForge

final class MockSpeechService: SpeechServiceProtocol {
    weak var delegate: SpeechServiceDelegate?
    var availableVoices: [AVSpeechSynthesisVoice] = []

    private(set) var spokenTexts: [String] = []
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var stopCount = 0
    private(set) var currentRate: Float = AVSpeechUtteranceDefaultSpeechRate
    private(set) var currentVoice: String?

    func speak(_ text: String) { spokenTexts.append(text) }
    func pause() { pauseCount += 1 }
    func resume() { resumeCount += 1 }
    func stop() { stopCount += 1 }
    func setRate(_ rate: Float) { currentRate = rate }
    func setVoice(_ identifier: String?) { currentVoice = identifier }

    func simulateFinish() {
        delegate?.speechServiceDidFinishUtterance()
    }

    func simulateWillSpeak(range: NSRange, in utterance: String) {
        delegate?.speechServiceWillSpeakRange(range, in: utterance)
    }
}
