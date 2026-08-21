import SwiftData
import SwiftUI

/// Ask Mode: on-device semantic search over the current document (CLAUDE.md Phase 10/14), with
/// a real generated answer on top when Apple's on-device Foundation Model is available
/// (`FoundationModelAnswerService`) — grounded strictly in the retrieved passages below it, so
/// the answer stays checkable rather than a black box, and the passages remain visible even
/// when a generated answer is shown. Falls back to just the ranked passages, as before, when
/// the model isn't available.
struct AskModeView: View {
    let document: DocumentRecord
    @Environment(\.modelContext) private var modelContext
    @State private var query = ""
    @State private var results: [DocumentSearchService.SearchResult] = []
    @State private var generatedAnswer: String?
    @State private var hasSearched = false
    @State private var isSearching = false
    @State private var jumpTarget: SectionRecord?

    private var sections: [SectionRecord] {
        document.sections.sorted { $0.order < $1.order }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            if isSearching {
                ProgressView("Searching…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasSearched {
                emptyState
            } else if results.isEmpty {
                noResultsState
            } else {
                resultsList
            }
        }
        .navigationTitle("Ask")
        .navigationDestination(item: $jumpTarget) { section in
            PlayerView(document: document, modelContext: modelContext, startSectionId: section.id)
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Ask a question about this document…", text: $query)
                .textFieldStyle(.plain)
                .onSubmit(runSearch)
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    generatedAnswer = nil
                    hasSearched = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Ask a question and ReadForge will find the most relevant passages in this document — entirely on-device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: 8) {
            Text("No matching passages found.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
    }

    private var resultsList: some View {
        List {
            if let generatedAnswer {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Answer", systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.tint)
                        Text(generatedAnswer)
                            .font(.body)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                ForEach(results) { result in
                    Button {
                        jump(to: result)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(result.sectionTitle)
                                .font(.caption)
                                .foregroundStyle(.tint)
                            Text(result.passage)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(4)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                if generatedAnswer != nil {
                    Text("Source Passages")
                }
            }
        }
        .listStyle(.plain)
    }

    private func runSearch() {
        // `SectionRecord` snapshots are built here, on the main actor, into a plain `Sendable`
        // form — the actual embedding search then runs off the main actor. A multi-hundred-page
        // document could otherwise mean a multi-second synchronous call on the UI thread (every
        // other heavy call site in this app — OCR, cleanup, summarization — already backgrounds
        // its work; this one didn't), freezing the keyboard/UI with no spinner and no way back
        // out mid-search.
        let searchableSections = sections.map {
            DocumentSearchService.SearchableSection(id: $0.id, title: $0.title, text: $0.cleanText ?? $0.rawText)
        }
        let searchQuery = query

        isSearching = true
        generatedAnswer = nil
        Task.detached(priority: .userInitiated) {
            let found = DocumentSearchService().search(query: searchQuery, in: searchableSections)
            await MainActor.run {
                results = found
                hasSearched = true
                isSearching = false
            }

            // Grounded generation on top of retrieval — real on devices where Apple's
            // on-device Foundation Model is available, silently absent otherwise (the
            // passages themselves are already shown either way).
            guard #available(iOS 26.0, *) else { return }
            let answer = await FoundationModelAnswerService().answer(question: searchQuery, passages: found)
            await MainActor.run {
                generatedAnswer = answer
            }
        }
    }

    private func jump(to result: DocumentSearchService.SearchResult) {
        jumpTarget = sections.first { $0.id == result.sectionId }
    }
}
