import Foundation
import SwiftData
import Testing
@testable import ReadForge

@MainActor
struct PlayerViewModelTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: DocumentRecord.self, SectionRecord.self, PlaybackState.self, BookmarkRecord.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func makeDocument(context: ModelContext, sectionCount: Int) -> DocumentRecord {
        let document = DocumentRecord(title: "Test Doc", fileURL: URL(fileURLWithPath: "/tmp/test.pdf"))
        context.insert(document)
        for i in 0..<sectionCount {
            let section = SectionRecord(
                title: "Section \(i)", rawText: "This is the text for section number \(i) right here.",
                order: i, startPage: i + 1, endPage: i + 1
            )
            section.document = document
            context.insert(section)
        }
        return document
    }

    // Regression test: `selectSection(at:)` used to do nothing when playback was paused or
    // idle — the controller kept pointing at the OLD section entirely, so tapping Play after
    // switching chapters while paused resumed/replayed the wrong section, even though the UI
    // (section picker) already showed the new one selected.
    @Test func selectingASectionWhilePausedStopsRatherThanLeavingStalePausedState() throws {
        let ctx = try makeContext()
        let document = makeDocument(context: ctx, sectionCount: 2)
        let viewModel = PlayerViewModel(document: document, modelContext: ctx)
        viewModel.configure()
        viewModel.togglePlayPause() // idle -> playing, section 0
        viewModel.togglePlayPause() // playing -> paused

        #expect(viewModel.playbackState == .paused)
        #expect(viewModel.selectedSectionIndex == 0)

        viewModel.selectSection(at: 1)

        #expect(viewModel.selectedSectionIndex == 1, "The view model's own selection should always update")
        // Before the fix, this stayed `.paused` — the controller silently kept its OLD section
        // loaded and paused, so resuming would have played section 0's audio while every visible
        // affordance (section picker, chapter list) showed section 1 selected.
        #expect(viewModel.playbackState == .idle, "Switching sections while paused should reset playback rather than leave it silently pointing at the old section")

        viewModel.stop()
    }

    @Test func selectingASectionWhilePlayingSwitchesImmediately() throws {
        let ctx = try makeContext()
        let document = makeDocument(context: ctx, sectionCount: 2)
        let viewModel = PlayerViewModel(document: document, modelContext: ctx)
        viewModel.configure()
        viewModel.togglePlayPause() // idle -> playing, section 0

        #expect(viewModel.playbackState == .playing)

        viewModel.selectSection(at: 1)

        #expect(viewModel.selectedSectionIndex == 1)
        #expect(viewModel.playbackState == .playing, "Switching sections while actively playing should keep playing, now on the new section")

        viewModel.stop()
    }
}
