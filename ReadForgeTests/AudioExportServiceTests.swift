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
}
