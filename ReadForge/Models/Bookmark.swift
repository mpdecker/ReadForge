import Foundation
import SwiftData

@Model
final class BookmarkRecord {
    var id: UUID
    var document: DocumentRecord?
    var sectionId: UUID
    var sentenceIndex: Int
    var note: String?
    var createdAt: Date

    init(sectionId: UUID, sentenceIndex: Int, note: String? = nil) {
        id = UUID()
        self.sectionId = sectionId
        self.sentenceIndex = sentenceIndex
        self.note = note
        createdAt = Date()
    }
}
