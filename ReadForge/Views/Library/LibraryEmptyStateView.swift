import SwiftUI

struct LibraryEmptyStateView: View {
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
        }
        .padding()
    }
}
