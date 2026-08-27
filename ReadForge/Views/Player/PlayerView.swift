import SwiftUI
import SwiftData

struct PlayerView: View {
    let document: DocumentRecord
    @State private var viewModel: PlayerViewModel

    init(document: DocumentRecord, modelContext: ModelContext, startSectionId: UUID? = nil, startSentenceIndex: Int = 0) {
        self.document = document
        _viewModel = State(initialValue: PlayerViewModel(
            document: document, modelContext: modelContext,
            startSectionId: startSectionId, startSentenceIndex: startSentenceIndex
        ))
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
        .sensoryFeedback(.success, trigger: viewModel.bookmarkFeedbackTrigger)
        // Not `.errorAlert` — `errorMessage` here is a get-only computed property (proxying
        // `PlaybackController.lastErrorMessage`, cleared via `dismissError()`), not a settable
        // `Binding` source. Built as a real two-way `isPresented` anyway (routed through
        // `dismissError()`) rather than the old `.constant(...)`, which never let a swipe-to-
        // dismiss or iPad tap-outside actually clear the error.
        .alert("Playback Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in if !isPresented { viewModel.dismissError() } }
        )) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
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
                isAnimating: viewModel.playbackState == .playing,
                highlightRange: viewModel.currentWordRange
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
