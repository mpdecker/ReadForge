//
//  DocumentProcessingService.swift
//  ReadForge
//
//  Created by Matthieu Decker on 5/10/26.
//

import Foundation
import SwiftData

/// Protocol for document processing services
protocol DocumentProcessingService {
    func processDocument(_ document: DocumentRecord, context: ModelContext) async throws
}


/// Protocol for text cleanup services
protocol TextCleaningService {
    func cleanup(_ text: String) -> String
}

/// Protocol for section detection services
protocol SectionDetectionService {
    func detect(pages: [PageText], outlineEntries: [(title: String, pageIndex: Int)], cleanedText: String) -> [SectionData]
}

/// Protocol for document import services
protocol DocumentImporting {
    func importDocument(from url: URL) throws -> DocumentRecord
}

/// Protocol for storage-oriented services (distinct from the `StorageService` struct helpers).
protocol DocumentStorageServicing {
    func updateProgress(document: DocumentRecord, sectionId: UUID, sentenceIndex: Int, characterOffset: Int, context: ModelContext)
    func fetchDocument(id: UUID, context: ModelContext) -> DocumentRecord?
    func saveContext(_ context: ModelContext) throws
}

/// Protocol for playback services
protocol PlaybackService {
    func play(document: DocumentRecord, section: SectionRecord, from sentenceIndex: Int?)
    func pause()
    func resume()
    func stop()
    func skipBack()
    func skipForward()
}

/// Protocol for speech services
protocol SpeechService {
    func speak(_ text: String, rate: Float) async throws
    func stop()
    var isSpeaking: Bool { get }
}

/// Protocol for AI model management
protocol AIModelManaging {
    var isLoaded: Bool { get }
    var modelName: String? { get }
    
    func loadModel(at url: URL) async throws
    func unloadModel()
    func runCleanup(on text: String) async -> String?
}
