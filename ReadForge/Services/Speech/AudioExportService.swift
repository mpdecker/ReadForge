import Foundation
import AVFoundation

/// Exports narrated audio as a single shareable file (CLAUDE.md v2.0 milestone: "audio export").
///
/// Deliberately always synthesizes fresh rather than trying to splice together previously
/// cached per-sentence clips from `AudioCacheService` — reusing those would mean reading back
/// each `.caf`'s PCM samples and re-writing them into one continuous file, format-matching
/// bookkeeping (sample rate, channel count) this session has no way to verify against real
/// audio output. Exporting is an occasional, explicit action rather than a hot path, so the
/// extra synthesis cost is a reasonable tradeoff for a much simpler, more obviously-correct
/// implementation, built on the exact same `AVSpeechSynthesizer.write` buffer-append pattern
/// `AudioCacheService` already uses successfully.
///
/// Exports as WAV (plain linear PCM), not the cache's own `.caf` container — broader
/// compatibility once the user shares the result outside ReadForge.
struct AudioExportService {
    enum ExportError: LocalizedError {
        case noContent

        var errorDescription: String? {
            "There's no text to export as audio."
        }
    }

    /// Synthesizes every sentence across `sections`, in order, into one continuous audio file
    /// and returns its URL. `progress` (if provided) is called after each sentence completes,
    /// with (sentences done, total sentences) — export can take a while for a whole book, so
    /// callers should show real progress rather than an indeterminate spinner.
    func export(
        sections: [(title: String, text: String)],
        voiceId: String?,
        rate: Float,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> URL {
        let allSentences = sections.flatMap { SentenceChunker.sentences(in: $0.text) }
        guard !allSentences.isEmpty else { throw ExportError.noContent }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadForge-Export-\(UUID().uuidString).wav")

        let holder = AudioFileHolder()
        for (index, sentence) in allSentences.enumerated() {
            try await Self.speakAndAppend(sentence, voiceId: voiceId, rate: rate, destination: destination, holder: holder)
            progress?(index + 1, allSentences.count)
        }
        return destination
    }

    // MARK: - Private

    /// Keeps one `AVAudioFile` open across every sentence in the loop above — it's only ever
    /// created once, on the very first audio buffer of the very first sentence, and every
    /// subsequent sentence's buffers are appended to that same open file, producing one
    /// continuous recording rather than one file per sentence.
    private final class AudioFileHolder: @unchecked Sendable {
        var audioFile: AVAudioFile?
    }

    /// Drives one utterance's `AVSpeechSynthesizer.write` callback to completion, appending its
    /// buffers to `holder`'s (possibly just-created) audio file. Same completion-callback
    /// pattern as `AudioCacheService.write` — see that type's doc comment for why `resumed`
    /// guards against double-resuming the continuation.
    private static func speakAndAppend(
        _ text: String, voiceId: String?, rate: Float, destination: URL, holder: AudioFileHolder
    ) async throws {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.voice = voiceId.flatMap { AVSpeechSynthesisVoice(identifier: $0) } ?? AVSpeechSynthesisVoice(language: "en-US")
        let synthesizer = AVSpeechSynthesizer()

        final class State: @unchecked Sendable {
            var resumed = false
        }
        let state = State()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            synthesizer.write(utterance) { buffer in
                guard !state.resumed, let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }

                if pcmBuffer.frameLength == 0 {
                    state.resumed = true
                    continuation.resume()
                    return
                }
                do {
                    if holder.audioFile == nil {
                        holder.audioFile = try AVAudioFile(forWriting: destination, settings: pcmBuffer.format.settings)
                    }
                    try holder.audioFile?.write(from: pcmBuffer)
                } catch {
                    state.resumed = true
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
