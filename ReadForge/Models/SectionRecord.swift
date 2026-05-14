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

    @Relationship(inverse: \DocumentRecord.sections) var document: DocumentRecord?

    init(title: String, rawText: String, order: Int, startPage: Int, endPage: Int) {
        self.id = UUID()
        self.title = title
        self.rawText = rawText
        self.order = order
        self.startPage = startPage
        self.endPage = endPage
        self.createdAt = Date()
    }
}
