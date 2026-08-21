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
    @Relationship(deleteRule: .cascade) var sections: [SectionRecord] = []
    @Relationship(deleteRule: .cascade) var bookmarks: [BookmarkRecord] = []
    @Relationship(deleteRule: .cascade) var playbackState: PlaybackState?

    var fileURL: URL { URL(fileURLWithPath: filePath) }

    var processingStatus: ProcessingStatus {
        get { ProcessingStatus(rawValue: statusRaw) ?? .imported }
        set { statusRaw = newValue.rawValue }
    }

    var wordCount: Int {
        sections.reduce(0) { $0 + ($1.cleanText ?? $1.rawText).split(separator: " ").count }
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
