import Foundation
import SwiftData

@Model
final class SectionRecord {
    var id: UUID
    var title: String
    var rawText: String
    var cleanText: String?
    var order: Int
    var startPage: Int
    var endPage: Int
    var createdAt: Date
    /// Precomputed from `cleanText ?? rawText` whenever either is set (init, and
    /// `refreshWordCount()` after cleanup/restore) — `DocumentRecord.wordCount` sums these
    /// instead of splitting every section's full text on every access. That computed property is
    /// read from the library list row for every visible document on every render/scroll, and
    /// re-splitting potentially hundreds of pages of text just to show a "~N min" label
    /// contradicted CLAUDE.md's "never load a full document into memory" / "load sections on
    /// demand."
    var wordCount: Int = 0

    @Relationship(inverse: \DocumentRecord.sections) var document: DocumentRecord?

    init(title: String, rawText: String, order: Int, startPage: Int, endPage: Int) {
        self.id = UUID()
        self.title = title
        self.rawText = rawText
        self.order = order
        self.startPage = startPage
        self.endPage = endPage
        self.createdAt = Date()
        self.wordCount = Self.countWords(rawText)
    }

    /// Call after setting `cleanText` (or `rawText`) outside of `init` — cleanup/restore are the
    /// only two call sites that do this (see `LibraryViewModel` and `BackupService`).
    func refreshWordCount() {
        wordCount = Self.countWords(cleanText ?? rawText)
    }

    private static func countWords(_ text: String) -> Int {
        text.split(separator: " ").count
    }
}
