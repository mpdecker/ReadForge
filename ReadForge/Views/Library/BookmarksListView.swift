import SwiftUI
import SwiftData

/// Browse, jump to, and delete bookmarks for a document. Adding a bookmark from the player
/// (`PlayerViewModel.addBookmark()`) has existed since the MVP build order's step 11, but there
/// was previously no way to see them again afterward — this closes that gap.
struct BookmarksListView: View {
    let document: DocumentRecord
    @Environment(\.modelContext) private var modelContext
    @State private var jumpTarget: BookmarkRecord?

    private var bookmarks: [BookmarkRecord] {
        document.bookmarks.sorted { $0.createdAt > $1.createdAt }
    }

    private var sectionsById: [UUID: SectionRecord] {
        Dictionary(uniqueKeysWithValues: document.sections.map { ($0.id, $0) })
    }

    var body: some View {
        Group {
            if bookmarks.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Bookmarks")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $jumpTarget) { bookmark in
            PlayerView(
                document: document, modelContext: modelContext,
                startSectionId: bookmark.sectionId, startSentenceIndex: bookmark.sentenceIndex
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No bookmarks yet")
                .font(.headline)
            Text("Tap the bookmark button while listening to save your place.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(bookmarks) { bookmark in
                Button {
                    jumpTarget = bookmark
                } label: {
                    row(for: bookmark)
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: delete)
        }
    }

    private func row(for bookmark: BookmarkRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sectionsById[bookmark.sectionId]?.title ?? "Unknown section")
                .font(.subheadline)
                .foregroundStyle(.primary)
            if let note = bookmark.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(bookmark.createdAt, style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func delete(at offsets: IndexSet) {
        // `bookmarks` re-sorts `document.bookmarks` fresh on every access, but `offsets` is
        // computed once against the pre-delete ordering. Looking it up again inside the loop
        // after each deletion has already shrunk `document.bookmarks` let a multi-row delete
        // (List Edit mode → select 2+ rows → Delete, delivered as one IndexSet) index past the
        // end of the now-shorter array — a crash — or silently delete the wrong bookmark once
        // indices no longer lined up. Snapshotting once before the loop fixes both.
        let snapshot = bookmarks
        for index in offsets {
            let bookmark = snapshot[index]
            document.bookmarks.removeAll { $0.id == bookmark.id }
            modelContext.delete(bookmark)
        }
        try? modelContext.save()
    }
}
