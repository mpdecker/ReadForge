import SwiftUI
import SwiftData

struct LibraryView: View {
    /// The toolbar's import action. Distinct from the empty state's
    /// ``LibraryEmptyStateView/importButtonIdentifier`` because both are on screen at once when
    /// the library is empty — a shared identifier makes the query ambiguous.
    static let importButtonIdentifier = "ImportDocumentToolbar"

    @Query(sort: \DocumentRecord.importedAt, order: .reverse) private var documents: [DocumentRecord]
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = LibraryViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if documents.isEmpty && viewModel.processingDocumentIds.isEmpty {
                    LibraryEmptyStateView { viewModel.showImporter = true }
                } else {
                    List(documents) { doc in
                        NavigationLink(value: doc) {
                            DocumentRowView(document: doc,
                                           isProcessing: viewModel.processingDocumentIds.contains(doc.id))
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("ReadForge")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Import", systemImage: "plus") { viewModel.showImporter = true }
                        .accessibilityIdentifier(LibraryView.importButtonIdentifier)
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
            .errorAlert($viewModel.errorMessage)
        }
    }
}
