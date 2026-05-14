import Foundation
import SwiftData

@Model
final class PlaybackState {
    var id: UUID
    var documentId: UUID
    var sectionId: UUID
    var sentenceIndex: Int
    var characterOffset: Int
    var lastPlayedAt: Date
    var playbackRate: Double
    var voiceIdentifier: String?
    
    init(documentId: UUID, sectionId: UUID, sentenceIndex: Int = 0, characterOffset: Int = 0) {
        self.id = UUID()
        self.documentId = documentId
        self.sectionId = sectionId
        self.sentenceIndex = sentenceIndex
        self.characterOffset = characterOffset
        self.lastPlayedAt = Date()
        self.playbackRate = 1.0
    }
}
