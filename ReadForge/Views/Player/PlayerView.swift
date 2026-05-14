import SwiftUI
import SwiftData

struct PlayerView: View {
    let document: DocumentRecord
    @State private var viewModel: PlayerViewModel

    init(document: DocumentRecord, modelContext: ModelContext) {
        self.document = document
        _viewModel = State(initialValue: PlayerViewModel(document: document, modelContext: modelContext))
    }

    var body: some View {
        Group {
            if viewModel.isEmpty {
                EmptyStateView.noPlayableContent
            } else {
                playerContent
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.configure()
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    // MARK: - Player Content

    private var playerContent: some View {
        VStack(spacing: 0) {
            // Section picker
            if viewModel.hasMultipleSections {
                SectionPickerView(
                    sections: viewModel.sections,
                    selectedIndex: Binding(
                        get: { viewModel.selectedSectionIndex },
                        set: { viewModel.selectSection(at: $0) }
                    ),
                    onSelectionChange: { index in
                        viewModel.selectSection(at: index)
                    }
                )
            }

            Divider()

            // Current sentence display
            SentenceDisplayView(
                sentence: viewModel.displayedSentence,
                isAnimating: viewModel.playbackState == .playing
            )

            Spacer()

            // Controls
            PlayerControlsView(viewModel: viewModel)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Bookmark", systemImage: "bookmark") {
                    viewModel.addBookmark()
                }
            }
        }
    }
}
