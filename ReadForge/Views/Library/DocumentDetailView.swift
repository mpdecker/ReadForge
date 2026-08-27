import SwiftUI
import SwiftData

/// Identifies one export request — either a single chapter or the whole book — for
/// `.sheet(item:)` to present `AudioExportView` with.
private struct AudioExportRequest: Identifiable {
    let id = UUID()
    let title: String
    let sections: [(title: String, text: String)]
}

/// Where to open the player to — tapping a specific chapter row previously always opened the
/// generic resume/default position (`showPlayer = true` was identical for every row, regardless
/// of which section was tapped), so tapping "Chapter 7" silently played whatever chapter progress
/// already pointed at instead. This distinguishes "resume/play bar" (no specific section) from
/// "this exact chapter row was tapped" (a specific section to jump straight to).
private enum PlayerDestination: Identifiable, Hashable {
    case resume
    case section(SectionRecord)

    var id: String {
        switch self {
        case .resume: return "resume"
        case .section(let section): return section.id.uuidString
        }
    }
}

struct DocumentDetailView: View {
    let document: DocumentRecord
    @Environment(\.modelContext) private var modelContext
    @State private var playerDestination: PlayerDestination?
    @State private var precachingSectionId: UUID?
    @State private var precachedSectionIds: Set<UUID> = []
    @State private var precacheTask: Task<Void, Never>?
    @State private var summarySection: SectionRecord?
    @State private var exportRequest: AudioExportRequest?
    private let audioCache = AudioCacheService.shared

    private var sections: [SectionRecord] {
        document.sections.sorted { $0.order < $1.order }
    }

    var body: some View {
        List {
            headerSection
            if document.processingStatus == .ready {
                chaptersSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            // `precachedSectionIds` is plain `@State` with nothing reading back from the actual
            // on-disk cache — since this view is recreated fresh every time it's pushed (via
            // `NavigationLink(value:)` from the library), popping back and re-entering the same
            // document previously reset the "Downloaded" checkmark to empty even though the
            // audio was still fully cached on disk.
            refreshPrecachedSectionIds()
        }
        .onDisappear {
            // Otherwise a "Download" left running when the user navigates away keeps
            // synthesizing every remaining sentence in the background indefinitely.
            precacheTask?.cancel()
        }
        .navigationDestination(item: $playerDestination) { destination in
            switch destination {
            case .resume:
                PlayerView(document: document, modelContext: modelContext)
            case .section(let section):
                PlayerView(document: document, modelContext: modelContext, startSectionId: section.id)
            }
        }
        .navigationDestination(item: $summarySection) { section in
            SectionSummaryView(section: section)
        }
        .sheet(item: $exportRequest) { request in
            AudioExportView(title: request.title, sections: request.sections)
        }
        .safeAreaInset(edge: .bottom) {
            if document.processingStatus == .ready && !sections.isEmpty {
                playBar
            }
        }
        .toolbar {
            if document.processingStatus == .ready && !sections.isEmpty {
                ToolbarItemGroup(placement: .primaryAction) {
                    NavigationLink {
                        BookmarksListView(document: document)
                    } label: {
                        Label("Bookmarks", systemImage: "bookmark")
                    }
                    NavigationLink {
                        AskModeView(document: document)
                    } label: {
                        Label("Ask", systemImage: "text.magnifyingglass")
                    }
                    Menu {
                        Button {
                            exportRequest = AudioExportRequest(
                                title: document.title,
                                sections: sections.map { (title: $0.title, text: $0.cleanText ?? $0.rawText) }
                            )
                        } label: {
                            Label("Export Entire Book", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                statusRow
                if document.processingStatus == .ready {
                    Divider()
                    HStack {
                        Label("\(document.pageCount) pages", systemImage: "doc.text")
                        Spacer()
                        Label(listeningTimeLabel, systemImage: "headphones")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var chaptersSection: some View {
        Section("Chapters") {
            ForEach(sections) { section in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.title)
                            .font(.body)
                        Text(wordCountLabel(for: section))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if precachingSectionId == section.id {
                        ProgressView().controlSize(.small)
                    } else if precachedSectionIds.contains(section.id) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.tint)
                            .accessibilityLabel("Downloaded for offline listening")
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture { playerDestination = .section(section) }
                .swipeActions(edge: .leading) {
                    Button {
                        precacheSection(section)
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .tint(.blue)
                    .disabled(precachingSectionId != nil)
                }
                .swipeActions(edge: .trailing) {
                    Button {
                        summarySection = section
                    } label: {
                        Label("Summary", systemImage: "text.redaction")
                    }
                    .tint(.indigo)
                    Button {
                        exportRequest = AudioExportRequest(
                            title: section.title,
                            sections: [(title: section.title, text: section.cleanText ?? section.rawText)]
                        )
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .tint(.green)
                }
            }
        }
    }

    private var playBar: some View {
        Button {
            playerDestination = .resume
        } label: {
            Label(resumeLabel, systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.tint)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var statusRow: some View {
        switch document.processingStatus {
        case .ready:
            Label("Ready to play", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .extracting:
            Label("Extracting text…", systemImage: "arrow.trianglehead.2.clockwise")
                .foregroundStyle(.orange)
        case .cleaning:
            Label("Cleaning up text…", systemImage: "arrow.trianglehead.2.clockwise")
                .foregroundStyle(.orange)
        case .performingOCR:
            Label("Scanning pages (OCR)…", systemImage: "text.viewfinder")
                .foregroundStyle(.orange)
        case .needsOCR:
            VStack(alignment: .leading, spacing: 4) {
                Label("Couldn't read this scan", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("On-device text recognition couldn't extract readable text from this PDF — the scan quality may be too low.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed:
            Label("Processing failed", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .imported:
            Label("Queued for processing…", systemImage: "clock")
                .foregroundStyle(.secondary)
        }
    }

    private var listeningTimeLabel: String {
        let mins = document.estimatedListeningMinutes
        if mins < 60 { return "\(Int(mins)) min" }
        return "\(Int(mins / 60))h \(Int(mins) % 60)m"
    }

    private var resumeLabel: String {
        document.playbackState != nil ? "Resume" : "Play"
    }

    private func wordCountLabel(for section: SectionRecord) -> String {
        let words = (section.cleanText ?? section.rawText).split(separator: " ").count
        let mins = max(1, Int(Double(words) / 160))
        return "\(mins) min"
    }

    /// Pre-renders every sentence in a section into the audio cache (CLAUDE.md Phase 15) so it's
    /// ready to play back without live synthesis — e.g. before a flight. This only populates the
    /// cache; it doesn't change how the live player produces audio.
    private func precacheSection(_ section: SectionRecord) {
        precachingSectionId = section.id
        let documentId = document.id
        let sectionId = section.id
        let sentences = SentenceChunker().chunk(section.cleanText ?? section.rawText)
        // Shared with `PlayerViewModel.configure()` so a precache and live playback always
        // derive the identical cache key — they used to read these UserDefaults keys
        // independently, which was harmless while both hard-coded the same nil/1.0 fallback,
        // but the live-playback side never actually got wired to Settings' choices at all, so
        // the two silently disagreed for any user who'd picked a non-default voice/speed.
        let (voiceId, rate) = PlaybackController.defaultVoiceAndRate()

        precacheTask = Task {
            for sentence in sentences {
                guard !Task.isCancelled else { return }
                let key = audioCache.cacheKey(
                    documentId: documentId, sectionId: sectionId, voiceId: voiceId, rate: rate, text: sentence
                )
                _ = try? await audioCache.synthesizeAndCache(text: sentence, voiceId: voiceId, rate: rate, key: key)
            }
            guard !Task.isCancelled else { return }
            precachingSectionId = nil
            precachedSectionIds.insert(sectionId)
        }
    }

    /// Checks each section's sentences against the on-disk cache (same key derivation as
    /// `precacheSection`) so the "Downloaded" checkmark reflects reality after this view is
    /// re-created, rather than always starting empty.
    private func refreshPrecachedSectionIds() {
        let documentId = document.id
        let sectionsSnapshot = sections.map { (id: $0.id, text: $0.cleanText ?? $0.rawText) }
        let (voiceId, rate) = PlaybackController.defaultVoiceAndRate()

        Task {
            var found: Set<UUID> = []
            for section in sectionsSnapshot {
                guard !Task.isCancelled else { return }
                let sentences = SentenceChunker().chunk(section.text)
                guard !sentences.isEmpty else { continue }
                var allCached = true
                for sentence in sentences {
                    let key = audioCache.cacheKey(
                        documentId: documentId, sectionId: section.id, voiceId: voiceId, rate: rate, text: sentence
                    )
                    if await audioCache.cachedFileURL(forKey: key) == nil {
                        allCached = false
                        break
                    }
                }
                if allCached { found.insert(section.id) }
            }
            guard !Task.isCancelled else { return }
            precachedSectionIds = found
        }
    }
}
