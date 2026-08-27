import Foundation
import SwiftData

enum ProcessingStatus: String, CaseIterable, Codable {
    case imported
    case extracting
    case cleaning
    case ready
    case performingOCR
    case needsOCR
    case failed
}

@Model
final class DocumentRecord {
    var id: UUID
    var title: String
    var author: String?
    var filePath: String
    var pageCount: Int
    var importedAt: Date
    private var statusRaw: String
    var languageCode: String?
    /// True only when a backup restore couldn't find this document's original file in the
    /// archive (e.g. it was iCloud-offloaded or already deleted at export time). Playback itself
    /// never needs the original file back (audio comes from `sections`' stored raw/clean text),
    /// but any future re-extraction/re-OCR feature must check this before trying to reopen
    /// `fileURL` — a restored document with no source file previously got a `filePath` of
    /// `/dev/null`, which is misleading: `/dev/null` is a real device node, so a naive
    /// `FileManager.fileExists(atPath:)` check on it reports `true`, silently hiding the fact
    /// that nothing real is there.
    var sourceFileMissing: Bool = false
    @Relationship(deleteRule: .cascade) var sections: [SectionRecord] = []
    @Relationship(deleteRule: .cascade) var bookmarks: [BookmarkRecord] = []
    @Relationship(deleteRule: .cascade) var playbackState: PlaybackState?

    var fileURL: URL { URL(fileURLWithPath: filePath) }

    var processingStatus: ProcessingStatus {
        get { ProcessingStatus(rawValue: statusRaw) ?? .imported }
        set { statusRaw = newValue.rawValue }
    }

    /// Sums each section's precomputed `wordCount` rather than re-splitting every section's full
    /// text on every access — see `SectionRecord.wordCount`'s doc comment.
    var wordCount: Int {
        sections.reduce(0) { $0 + $1.wordCount }
    }

    var estimatedListeningMinutes: Double { Double(wordCount) / 160.0 }

    init(title: String, fileURL: URL, author: String? = nil) {
        id = UUID()
        self.title = title
        self.author = author
        filePath = fileURL.path
        pageCount = 0
        importedAt = Date()
        statusRaw = ProcessingStatus.imported.rawValue
    }
}
