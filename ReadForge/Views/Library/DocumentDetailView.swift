import SwiftUI
import SwiftData

struct DocumentDetailView: View {
    let document: DocumentRecord
    @Environment(\.modelContext) private var modelContext
    @State private var showPlayer = false

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
        .navigationDestination(isPresented: $showPlayer) {
            PlayerView(document: document, modelContext: modelContext)
        }
        .safeAreaInset(edge: .bottom) {
            if document.processingStatus == .ready && !sections.isEmpty {
                playBar
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
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture { showPlayer = true }
            }
        }
    }

    private var playBar: some View {
        Button {
            showPlayer = true
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
        case .needsOCR:
            VStack(alignment: .leading, spacing: 4) {
                Label("Scanned PDF detected", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("This PDF has no text layer. OCR support is coming in a future update.")
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
}
