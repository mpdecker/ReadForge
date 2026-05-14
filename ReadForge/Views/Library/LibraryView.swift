import SwiftUI
import SwiftData

struct LibraryView: View {
    @Query(sort: \DocumentRecord.importedAt, order: .reverse) private var documents: [DocumentRecord]
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = LibraryViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if documents.isEmpty && viewModel.processingDocumentId == nil {
                    LibraryEmptyStateView { viewModel.showImporter = true }
                } else {
                    List(documents) { doc in
                        NavigationLink(value: doc) {
                            DocumentRowView(document: doc,
                                           isProcessing: viewModel.processingDocumentId == doc.id)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("ReadForge")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Import", systemImage: "plus") { viewModel.showImporter = true }
                }
            }
            .navigationDestination(for: DocumentRecord.self) { doc in
                DocumentDetailView(document: doc)
            }
            .fileImporter(
                isPresented: $viewModel.showImporter,
                allowedContentTypes: DocumentFormat.utTypes,
                allowsMultipleSelection: false
            ) { result in
                viewModel.handleImport(result, context: modelContext)
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}
