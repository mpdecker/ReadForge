//
//  PlayerViewModel.swift
//  ReadForge
//
//  Created by Matthieu Decker on 5/10/26.
//

import SwiftUI
import SwiftData

@Observable
@MainActor
final class PlayerViewModel {
    
    // MARK: - Properties
    
    let document: DocumentRecord
    private let modelContext: ModelContext
    
    private var controller: PlaybackController
    var selectedSectionIndex: Int = 0
    
    // MARK: - Computed Properties
    
    var sections: [SectionRecord] {
        document.sections.sorted { $0.order < $1.order }
    }
    
    var currentSection: SectionRecord? {
        sections.indices.contains(selectedSectionIndex) ? sections[selectedSectionIndex] : nil
    }
    
    var playbackState: PlaybackController.State {
        controller.playbackState
    }
    
    var currentSentenceIndex: Int {
        controller.currentSentenceIndex
    }
    
    var playbackRate: Float {
        get { controller.playbackRate }
        set { controller.playbackRate = newValue }
    }
    
    var displayedSentence: String {
        let section = controller.currentSection ?? currentSection
        guard let section else { return "" }
        let sentences = SentenceChunker().chunk(section.cleanText ?? section.rawText)
        guard sentences.indices.contains(controller.currentSentenceIndex) else { return "" }
        return sentences[controller.currentSentenceIndex]
    }
    
    var progressLabel: String {
        guard let section = currentSection else { return "" }
        let total = SentenceChunker().chunk(section.cleanText ?? section.rawText).count
        return "\(controller.currentSentenceIndex + 1) of \(total)"
    }
    
    var canSkipBack: Bool {
        !(controller.playbackState == .idle && controller.currentSentenceIndex == 0)
    }
    
    var hasMultipleSections: Bool {
        sections.count > 1
    }
    
    var isEmpty: Bool {
        sections.isEmpty
    }
    
    // MARK: - Initialization
    
    init(document: DocumentRecord, modelContext: ModelContext) {
        self.document = document
        self.modelContext = modelContext
        self.controller = PlaybackController()
    }
    
    // MARK: - Public Methods
    
    /// Configures the player for use
    func configure() {
        controller.configure(with: modelContext)
        controller.configureAudioSession()
        resumeIfNeeded()
    }
    
    /// Stops playback
    func stop() {
        controller.stop()
    }
    
    /// Handles play/pause action
    func togglePlayPause() {
        switch controller.playbackState {
        case .idle:
            if let section = currentSection {
                controller.play(document: document, section: section)
            }
        case .playing:
            controller.pause()
        case .paused:
            controller.resume()
        }
    }
    
    /// Skips backward 15 seconds
    func skipBack() {
        controller.skipBack()
    }
    
    /// Skips forward 15 seconds
    func skipForward() {
        controller.skipForward()
    }
    
    /// Changes the selected section
    func selectSection(at index: Int) {
        guard index != selectedSectionIndex else { return }
        selectedSectionIndex = index
        
        if controller.playbackState == .playing, let section = currentSection {
            controller.play(document: document, section: section)
        }
    }
    
    /// Adds a bookmark at current position
    func addBookmark() {
        guard let section = currentSection else { return }
        let bookmark = BookmarkRecord(sectionId: section.id, sentenceIndex: controller.currentSentenceIndex)
        bookmark.document = document
        document.bookmarks.append(bookmark)
        modelContext.insert(bookmark)
        try? modelContext.save()
        
        ReadForgeLogger.debug(category: "Player", message: "Added bookmark at section: \(section.title), sentence: \(controller.currentSentenceIndex)")
    }
    
    // MARK: - Private Methods
    
    private func resumeIfNeeded() {
        guard let state = document.playbackState,
              let section = sections.first(where: { $0.id == state.sectionId }),
              let idx = sections.firstIndex(where: { $0.id == section.id })
        else { return }
        
        selectedSectionIndex = idx
        controller.play(document: document, section: section, from: state.sentenceIndex)
    }
}
