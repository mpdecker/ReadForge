import SwiftUI

struct DocumentRowView: View {
    let document: DocumentRecord
    let isProcessing: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(document.title)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    statusView
                    if document.processingStatus == .ready {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(listeningTimeLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if isProcessing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusView: some View {
        switch document.processingStatus {
        case .ready:
            EmptyView()
        case .extracting:
            Text("Extracting…")
                .font(.caption)
                .foregroundStyle(.orange)
        case .cleaning:
            Text("Cleaning…")
                .font(.caption)
                .foregroundStyle(.orange)
        case .performingOCR:
            Text("Scanning…")
                .font(.caption)
                .foregroundStyle(.orange)
        case .needsOCR:
            Label("Scan unreadable", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        case .imported:
            Text("Queued…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var listeningTimeLabel: String {
        let mins = document.estimatedListeningMinutes
        if mins < 1 { return "< 1 min" }
        if mins < 60 { return "\(Int(mins)) min" }
        return "\(Int(mins / 60))h \(Int(mins) % 60)m"
    }
}
