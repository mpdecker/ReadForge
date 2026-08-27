import Testing
import Foundation
@testable import ReadForge

struct AudioCacheServiceTests {
    @Test func cacheKeyIncludesAllSpecifiedComponents() {
        // CLAUDE.md's Storage section: "Audio cache keyed by: documentId + sectionId + voiceId
        // + speed + textHash" — a voice/speed change or edited text should naturally miss the
        // cache rather than serve stale audio.
        let cache = AudioCacheService()
        let documentId = UUID()
        let sectionId = UUID()

        let key1 = cache.cacheKey(documentId: documentId, sectionId: sectionId, voiceId: "com.apple.voice.a", rate: 1.0, text: "Hello world.")
        let key2 = cache.cacheKey(documentId: documentId, sectionId: sectionId, voiceId: "com.apple.voice.b", rate: 1.0, text: "Hello world.")
        let key3 = cache.cacheKey(documentId: documentId, sectionId: sectionId, voiceId: "com.apple.voice.a", rate: 1.5, text: "Hello world.")
        let key4 = cache.cacheKey(documentId: documentId, sectionId: sectionId, voiceId: "com.apple.voice.a", rate: 1.0, text: "Different text.")

        #expect(key1 != key2, "Different voice should produce a different key")
        #expect(key1 != key3, "Different speed should produce a different key")
        #expect(key1 != key4, "Different text should produce a different key")
    }

    @Test func cacheKeyIsDeterministic() {
        let cache = AudioCacheService()
        let documentId = UUID()
        let sectionId = UUID()
        let key1 = cache.cacheKey(documentId: documentId, sectionId: sectionId, voiceId: nil, rate: 1.0, text: "Same text.")
        let key2 = cache.cacheKey(documentId: documentId, sectionId: sectionId, voiceId: nil, rate: 1.0, text: "Same text.")
        #expect(key1 == key2)
    }

    // Regression test: two concurrent `synthesizeAndCache` calls for the identical key used to
    // both pass the "not cached yet" check and race to write the same destination file. This
    // exercises the single-flight fix — both calls should return the exact same, successfully
    // written file rather than racing or throwing.
    @Test func concurrentCallsForSameKeyDoNotRace() async throws {
        let cache = AudioCacheService()
        let key = "test-concurrent-\(UUID().uuidString)"

        async let first = try cache.synthesizeAndCache(text: "A short test sentence.", voiceId: nil, rate: 1.0, key: key)
        async let second = try cache.synthesizeAndCache(text: "A short test sentence.", voiceId: nil, rate: 1.0, key: key)

        let (url1, url2) = try await (first, second)
        #expect(url1 == url2)
        #expect(FileManager.default.fileExists(atPath: url1.path))

        try? FileManager.default.removeItem(at: url1)
    }

    // MARK: - Word timings
    //
    // `AudioCacheService` captures real per-word timing data via `AVSpeechSynthesizer`'s marker
    // callback (`write(_:toBufferCallback:toMarkerCallback:)`, iOS 16+) so `PlaybackController`
    // can highlight the current word during *cached* playback the same way it already does for
    // live TTS — `AVAudioPlayer` has no per-word callback of its own, so before this, cached
    // playback never highlighted anything.
    //
    // Verified empirically in this environment (not assumed): every voice actually installed in
    // this Simulator — all standard/"super-compact" quality, since Enhanced/Premium voices are a
    // separate download this environment doesn't have — produces zero marker callbacks for any
    // text. The marker mechanism appears to need a higher-quality voice than what's available
    // here, and I have no device with one downloaded to confirm that positive case. So this
    // suite tests what's actually verifiable: the capture pipeline runs without failing
    // (synthesis + caching still succeeds when zero markers arrive), and the graceful
    // "no timings available" fallback `PlaybackController`/`SentenceDisplayView` depend on
    // behaves correctly — not that markers are captured, which isn't true for any voice this
    // session can exercise.

    @Test func synthesizeAndCacheSucceedsRegardlessOfWhetherMarkersAreProduced() async throws {
        let cache = AudioCacheService()
        let key = "test-timings-\(UUID().uuidString)"
        let text = "This sentence has several distinct words in it."

        let audioURL = try await cache.synthesizeAndCache(text: text, voiceId: nil, rate: 1.0, key: key)
        defer {
            // Removes only this test's own files — `clearAll()` would wipe the whole shared
            // cache directory and could interfere with other tests running concurrently.
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: audioURL.deletingLastPathComponent().appendingPathComponent("\(key).words.json"))
        }

        #expect(FileManager.default.fileExists(atPath: audioURL.path))

        // Whatever this voice actually produced (verified: nothing, in this environment) must
        // come back as either `nil` or a well-formed, in-bounds, time-ordered list — never a
        // crash or a malformed result.
        if let timings = cache.wordTimingsSync(forKey: key) {
            for timing in timings {
                #expect(timing.location >= 0 && timing.location + timing.length <= text.count)
                #expect(timing.time >= 0)
            }
            let times = timings.map(\.time)
            #expect(times == times.sorted(), "Word timings should be in non-decreasing time order")
        }
    }

    @Test func wordTimingsSyncReturnsNilForUncachedKey() {
        let cache = AudioCacheService()
        #expect(cache.wordTimingsSync(forKey: "not-a-real-key-\(UUID().uuidString)") == nil)
    }

    @Test func wordTimingCodableRoundTrip() throws {
        let timing = AudioCacheService.WordTiming(location: 3, length: 5, time: 1.25)
        let data = try JSONEncoder().encode([timing])
        let decoded = try JSONDecoder().decode([AudioCacheService.WordTiming].self, from: data)
        #expect(decoded.count == 1)
        #expect(decoded[0].location == 3)
        #expect(decoded[0].length == 5)
        #expect(decoded[0].time == 1.25)
        #expect(decoded[0].range == NSRange(location: 3, length: 5))
    }
}
