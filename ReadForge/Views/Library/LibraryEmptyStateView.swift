import SwiftUI

struct LibraryEmptyStateView: View {
    /// The empty state's own import call to action, distinct from the toolbar's
    /// ``LibraryView/importButtonIdentifier`` since both are on screen together here.
    static let importButtonIdentifier = "ImportDocumentEmptyState"

    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No documents yet")
                .font(.title2)
            Text("Import a PDF to get started.")
                .foregroundStyle(.secondary)
            Button("Import PDF", action: onImport)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(Self.importButtonIdentifier)
        }
        .padding()
    }
}
