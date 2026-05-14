import Foundation
import SwiftData

// Thin helpers for common SwiftData queries used outside of SwiftUI views.
struct StorageService {
    static func fetchDocument(id: UUID, context: ModelContext) throws -> DocumentRecord? {
        let descriptor = FetchDescriptor<DocumentRecord>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    static func updateProgress(
        document: DocumentRecord,
        sectionId: UUID,
        sentenceIndex: Int,
        characterOffset: Int,
        context: ModelContext
    ) {
        if let state = document.playbackState {
            state.sectionId = sectionId
            state.sentenceIndex = sentenceIndex
            state.characterOffset = characterOffset
            state.lastPlayedAt = Date()
        } else {
            let state = PlaybackState(
                documentId: document.id,
                sectionId: sectionId,
                sentenceIndex: sentenceIndex,
                characterOffset: characterOffset
            )
            document.playbackState = state
            context.insert(state)
        }
        try? context.save()
    }
}
