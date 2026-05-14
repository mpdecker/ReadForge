import SwiftData
import SwiftUI

// Ask mode: local RAG Q&A against the current document. Phase 10.
struct AskModeView: View {
    let document: DocumentRecord

    var body: some View {
        VStack {
            Text("Ask Mode — coming in v1.5")
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Ask")
    }
}
