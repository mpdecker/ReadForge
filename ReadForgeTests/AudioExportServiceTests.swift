import Testing
import Foundation
@testable import ReadForge

struct AudioExportServiceTests {
    @Test func exportProducesANonEmptyWAVFile() async throws {
        let sections = [
            (title: "Chapter One", text: "This is the first sentence. This is the second sentence."),
            (title: "Chapter Two", text: "A short chapter with one sentence only."),
        ]

        let url = try await AudioExportService().export(sections: sections, voiceId: nil, rate: 1.0)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(url.pathExtension == "wav")
        #expect(FileManager.default.fileExists(atPath: url.path))
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        #expect((size ?? 0) > 0, "Exported audio file should not be empty")
    }

    @Test func exportReportsProgressForEverySentence() async throws {
        let sections = [(title: "Section", text: "First sentence here. Second sentence here. Third sentence here.")]

        var progressCalls: [(Int, Int)] = []
        let url = try await AudioExportService().export(sections: sections, voiceId: nil, rate: 1.0) { done, total in
            progressCalls.append((done, total))
        }
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(!progressCalls.isEmpty)
        #expect(progressCalls.last?.0 == progressCalls.last?.1, "Final progress call should report completion")
    }

    @Test func exportWithNoContentThrows() async throws {
        await #expect(throws: AudioExportService.ExportError.self) {
            _ = try await AudioExportService().export(sections: [(title: "Empty", text: "")], voiceId: nil, rate: 1.0)
        }
    }

    // Regression test: nothing in the export loop previously checked for cancellation, so
    // cancelling the calling Task (e.g. the export sheet being swiped away) had no effect —
    // synthesis kept running to completion in the background and its finished temp file was
    // never cleaned up. `export` now checks cancellation between sentences and removes its
    // partial output on any thrown error, including cancellation.
    @Test func cancelledExportLeavesNoTempFileBehind() async throws {
        let longText = Array(repeating: "This is a sentence to synthesize aloud for this test.", count: 100)
            .joined(separator: " ")
        let sections = [(title: "Long", text: longText)]
        let before = tempExportFiles()

        let task = Task {
            try await AudioExportService().export(sections: sections, voiceId: nil, rate: 1.0)
        }
        try await Task.sleep(nanoseconds: 50_000_000) // let at least one sentence start
        task.cancel()

        do {
            // Finished before the cancellation landed — real output, not a leak; clean it up so
            // it doesn't get counted as one below.
            let url = try await task.value
            try? FileManager.default.removeItem(at: url)
        } catch {
            // Expected: CancellationError, or a synthesis error surfaced by the cancellation.
        }

        let after = tempExportFiles()
        #expect(after.subtracting(before).isEmpty, "A cancelled export must not leave a temp .wav file behind")
    }

    private func tempExportFiles() -> Set<String> {
        let dir = FileManager.default.temporaryDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return Set(names.filter { $0.hasPrefix("ReadForge-Export-") })
    }
}
