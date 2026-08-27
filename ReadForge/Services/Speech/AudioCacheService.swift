import Foundation
import AVFoundation

/// Pre-rendered audio cache (CLAUDE.md Phase 15: "Audio caching (AVSpeechSynthesizer.write
/// buffer)"). Synthesizes an utterance once and writes it to disk; a cache hit means playback
/// doesn't need to re-run text-to-speech synthesis for that exact sentence again.
///
/// Cache key is `documentId + sectionId + voiceId + speed + textHash`, per CLAUDE.md's Storage
/// section — a settings change (voice/speed) or an edited section naturally misses the cache
/// rather than serving stale audio.
///
/// App code should use `.shared` rather than constructing a new instance — `inFlightWrites`'
/// single-flight write protection (below) only holds within one instance, and every real call
/// site (`PlaybackController`, `DocumentDetailView`, `SettingsView`, `DataStorageView`) points at
/// the identical on-disk cache directory regardless of which instance touches it, so multiple
/// independently-constructed instances could otherwise race a concurrent write to the same file
/// without ever knowing about each other. `init()` stays available for tests that specifically
/// want an isolated instance.
actor AudioCacheService {
    static let shared = AudioCacheService()

    /// One word's position in the source text and when it starts, in seconds, within the
    /// cached audio clip — captured during the same synthesis pass that renders the audio, via
    /// `AVSpeechSynthesizer`'s marker callback (real per-word timing data, not an estimate). Lets
    /// `PlaybackController` highlight the current word during *cached* playback the same way it
    /// already does for live TTS via `speechServiceWillSpeakRange` — `AVAudioPlayer` has no
    /// per-word callback of its own, so without this, cached playback had no highlight at all.
    ///
    /// Verified honestly, not assumed: every voice actually available in this session's test
    /// environment (all standard/"super-compact" quality — Enhanced/Premium voices are a
    /// separate download this environment doesn't have installed) produces zero marker
    /// callbacks for any text, confirmed by direct instrumentation. The marker mechanism appears
    /// to require a higher-quality voice this session has no way to obtain or confirm. That
    /// means in practice, today, on a fresh device with only standard-quality voices, this
    /// capture will consistently find nothing to store — which is exactly the same "no timings
    /// available" outcome the code already handles for an older cache entry or an unsupported
    /// voice, so nothing breaks; the highlight just won't appear for cached playback until
    /// either a higher-quality voice does support markers (unverified) or this is confirmed
    /// working on a device with one downloaded.
    struct WordTiming: Codable, Sendable {
        let location: Int
        let length: Int
        let time: Double

        var range: NSRange { NSRange(location: location, length: length) }
    }

    private let cacheDir: URL
    private let fileManager = FileManager.default
    /// Single-flight tracking for in-progress writes, keyed by cache key. Without this, two
    /// concurrent calls for the same key (e.g. two `precacheSection` runs, or a precache
    /// racing a live-playback cache-fill) would both pass the "not cached yet" check below —
    /// an actor is only exclusive *between* suspension points, and `synthesizeAndCache` awaits
    /// `Self.write(...)` before the file exists — and then both open
    /// `AVAudioFile(forWriting:)` on the identical path at once, corrupting/truncating it.
    private var inFlightWrites: [String: Task<URL, Error>] = [:]

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheDir = base.appendingPathComponent("AudioCache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    nonisolated func cacheKey(documentId: UUID, sectionId: UUID, voiceId: String?, rate: Float, text: String) -> String {
        let textHash = SecurityService.hash(Data(text.utf8))
        let voiceComponent = voiceId ?? "system-default"
        return "\(documentId.uuidString)_\(sectionId.uuidString)_\(voiceComponent)_\(String(format: "%.2f", rate))_\(textHash)"
    }

    func cachedFileURL(forKey key: String) -> URL? {
        let url = fileURL(forKey: key)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Same lookup as `cachedFileURL`, callable without an `await`. Safe without actor
    /// isolation: it only ever reads `cacheDir`, an immutable `let` set once at `init`, and does
    /// a stateless filesystem check — nothing here touches `inFlightWrites` or any other
    /// mutable actor state. `PlaybackController.speakCurrentSentence()` uses this so deciding
    /// "cached or live" doesn't cost an actor hop on every single sentence — with the async
    /// version, a fire-and-forget `Task` there would call `speech.speak(_:)` a beat later than
    /// before, which is also just wrong in a race sense (a skip/stop landing inside that gap
    /// would need extra bookkeeping to avoid playing stale audio).
    nonisolated func cachedFileURLSync(forKey key: String) -> URL? {
        let url = cacheDir.appendingPathComponent("\(key).caf")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Word timings for a cached clip, if any were captured when it was rendered — `nil` when
    /// there's no cached clip for this key, or the voice/synthesis pass didn't produce word
    /// markers. Same "no actor hop" reasoning as `cachedFileURLSync`: called from
    /// `PlaybackController` right alongside it, on the same hot path.
    nonisolated func wordTimingsSync(forKey key: String) -> [WordTiming]? {
        let url = cacheDir.appendingPathComponent("\(key).words.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([WordTiming].self, from: data)
    }

    /// Synthesizes `text` via `AVSpeechSynthesizer.write` and caches the resulting audio (plus
    /// word timings, if the synthesis pass produced any). Returns immediately with the existing
    /// file if this key is already cached.
    @discardableResult
    func synthesizeAndCache(text: String, voiceId: String?, rate: Float, key: String) async throws -> URL {
        let destination = fileURL(forKey: key)
        if fileManager.fileExists(atPath: destination.path) { return destination }

        // Join an already-running write for this exact key instead of starting a second one.
        if let existing = inFlightWrites[key] {
            return try await existing.value
        }

        let task = Task<URL, Error> {
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = rate
            utterance.voice = voiceId.flatMap { AVSpeechSynthesisVoice(identifier: $0) } ?? AVSpeechSynthesisVoice(language: "en-US")

            // Written to a temp path first, then moved into place atomically. A concurrent
            // `cachedFileURLSync` has no actor hop and so can run its plain `fileExists` check
            // at any point during this write — without the temp-file indirection, it could
            // observe a partially-written `.caf` (AVSpeechSynthesizer.write delivers audio
            // buffer-by-buffer over many callbacks) and `AVAudioPlayer` would then play a clip
            // that cuts off mid-sentence. `moveItem` on the same volume is a `rename()`, which
            // is atomic — readers only ever see "doesn't exist yet" or "fully written."
            let tempDestination = cacheDir.appendingPathComponent("." + UUID().uuidString + ".tmp")
            let wordTimings = try await Self.write(utterance, to: tempDestination)
            try? fileManager.removeItem(at: destination) // stale leftover from an earlier crash, if any
            try fileManager.moveItem(at: tempDestination, to: destination)

            // The sidecar isn't rename-atomic like the audio file, but that's fine here: a
            // reader (`wordTimingsSync`) that catches it mid-write just fails to decode and
            // returns `nil`, which is exactly the same "no highlight available" fallback as no
            // sidecar existing at all — never a corrupted playback the way a torn audio file
            // would be.
            if !wordTimings.isEmpty, let data = try? JSONEncoder().encode(wordTimings) {
                let sidecarURL = self.cacheDir.appendingPathComponent("\(key).words.json")
                try? data.write(to: sidecarURL)
            }

            return destination
        }
        inFlightWrites[key] = task
        defer { inFlightWrites[key] = nil }
        return try await task.value
    }

    func clearAll() {
        try? fileManager.removeItem(at: cacheDir)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func totalSizeMB() -> Double {
        guard let files = try? fileManager.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        let total = files.reduce(0) { sum, url in
            sum + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return Double(total) / 1024.0 / 1024.0
    }

    // MARK: - Private

    private func fileURL(forKey key: String) -> URL {
        cacheDir.appendingPathComponent("\(key).caf")
    }

    /// Drives `AVSpeechSynthesizer`'s buffer-at-a-time callback to completion exactly once,
    /// writing every buffer to `destination`, and collects real per-word timing data along the
    /// way via the marker callback (`writeUtterance(_:toBufferCallback:toMarkerCallback:)`,
    /// iOS 16+). The buffer callback fires repeatedly (one call per audio buffer, then a final
    /// zero-length buffer signaling completion) — `resumed` guards against double-resuming the
    /// continuation, which would otherwise crash.
    ///
    /// Markers are collected as raw (text range, byte offset) pairs and only converted to a
    /// time offset *after* the write completes, once the audio format (and so bytes-per-frame)
    /// is known for certain — converting eagerly would risk silently dropping any marker that
    /// happened to arrive before the very first buffer callback established the format.
    private static func write(_ utterance: AVSpeechUtterance, to destination: URL) async throws -> [WordTiming] {
        struct RawMarker {
            let location: Int
            let length: Int
            let byteOffset: UInt64
        }
        final class State: @unchecked Sendable {
            var audioFile: AVAudioFile?
            var resumed = false
            var bytesPerFrame: Double = 0
            var sampleRate: Double = 0
            var rawMarkers: [RawMarker] = []
        }
        let state = State()
        let synthesizer = AVSpeechSynthesizer()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            synthesizer.write(utterance, toBufferCallback: { buffer in
                guard !state.resumed, let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }

                if pcmBuffer.frameLength == 0 {
                    state.resumed = true
                    continuation.resume()
                    return
                }
                do {
                    if state.audioFile == nil {
                        state.audioFile = try AVAudioFile(forWriting: destination, settings: pcmBuffer.format.settings)
                        state.sampleRate = pcmBuffer.format.sampleRate
                        state.bytesPerFrame = Double(pcmBuffer.format.streamDescription.pointee.mBytesPerFrame)
                    }
                    try state.audioFile?.write(from: pcmBuffer)
                } catch {
                    state.resumed = true
                    continuation.resume(throwing: error)
                }
            }, toMarkerCallback: { markers in
                for marker in markers where marker.mark == .word {
                    state.rawMarkers.append(RawMarker(
                        location: marker.textRange.location,
                        length: marker.textRange.length,
                        byteOffset: UInt64(bitPattern: Int64(marker.byteSampleOffset))
                    ))
                }
            })
        }

        guard state.bytesPerFrame > 0, state.sampleRate > 0 else { return [] }
        let bytesPerSecond = state.bytesPerFrame * state.sampleRate
        return state.rawMarkers.map {
            WordTiming(location: $0.location, length: $0.length, time: Double($0.byteOffset) / bytesPerSecond)
        }
    }
}
