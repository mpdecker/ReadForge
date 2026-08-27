import SwiftUI
import SwiftData
import Combine

@Observable
@MainActor
final class LibraryViewModel {
    var showImporter = false
    var errorMessage: String?
    /// A set, not a single optional id — the Import button was never disabled while an import
    /// was in flight, so starting a second import before the first finished used to overwrite
    /// this single value: document A's row spinner would vanish mid-processing (the moment B's
    /// import began) while B's row showed the spinner regardless of A's real state, and whichever
    /// document finished last would clear it even if the other was still processing.
    var processingDocumentIds: Set<UUID> = []

    private let serviceContainer = ServiceContainer.shared
    private let cache = CacheManager.shared

    func handleImport(_ result: Result<[URL], Error>, context: ModelContext) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await importAndProcess(url: url, context: context) }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func importAndProcess(url: URL, context: ModelContext) async {
        var record: DocumentRecord?
        do {
            // Get services asynchronously
            let importer = try await serviceContainer.documentImportService
            let extractorFactory = try await serviceContainer.extractionFactory
            let cleaner = try await serviceContainer.textCleanupService
            let detector = try await serviceContainer.sectionDetectionService
            let performance = try await serviceContainer.performanceCoordinator

            // Validate format before touching the file system
            guard let format = DocumentFormat(url: url) else {
                throw ImportError.unsupportedFormat
            }

            // Step 1 — copy file, create record
            let newRecord = try importer.importDocument(from: url)
            context.insert(newRecord)
            try context.save()
            record = newRecord
            processingDocumentIds.insert(newRecord.id)

            let fileURL  = newRecord.fileURL
            let extractor = extractorFactory.extractor(for: format)

            // Step 2 — extract metadata + pages (background)
            newRecord.processingStatus = .extracting
            try context.save()

            let (metadata, pages) = try await Task.detached(priority: .userInitiated) {
                [extractor, fileURL] in
                let meta  = extractor.extractMetadata(from: fileURL)
                let pages = try extractor.extractPages(from: fileURL)
                return (meta, pages)
            }.value

            // Apply metadata
            newRecord.pageCount = pages.count
            if let docTitle = metadata.title, !docTitle.isEmpty {
                newRecord.title = docTitle
            }
            if let docAuthor = metadata.author, !docAuthor.isEmpty {
                newRecord.author = docAuthor
            }

            var workingPages = pages

            if extractor.isLikelyScanned(pages) {
                guard format == .pdf else {
                    // OCR only applies to PDF's image-based pages; other formats that report
                    // "scanned" (none currently do — see `DocumentExtracting`'s default) have
                    // no raster fallback available.
                    newRecord.processingStatus = .needsOCR
                    try context.save()
                    processingDocumentIds.remove(newRecord.id)
                    return
                }

                newRecord.processingStatus = .performingOCR
                try context.save()

                let ocr = try await serviceContainer.ocrService
                let ocrPages = try await Task.detached(priority: .userInitiated) {
                    [ocr, fileURL] in try ocr.recognizeText(from: fileURL)
                }.value

                guard !extractor.isLikelyScanned(ocrPages) else {
                    // OCR still couldn't pull readable text (poor scan quality, handwriting).
                    newRecord.processingStatus = .needsOCR
                    try context.save()
                    processingDocumentIds.remove(newRecord.id)
                    return
                }
                workingPages = ocrPages
            }

            // Pause before the heaviest step (section detection over the whole document) if
            // the system is thermally throttled or critically low on battery, per CLAUDE.md's
            // "Pause AI processing when battery is low or device is hot".
            if !performance.shouldAllowHeavyOperations() {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }

            // Step 3 — clean + detect sections (background)
            newRecord.processingStatus = .cleaning
            try context.save()

            let outline = await Task.detached(priority: .userInitiated) {
                [extractor, fileURL] in
                extractor.outline(from: fileURL)
            }.value

            let useEnhancedCleanup = UserDefaults.standard.bool(forKey: "useEnhancedCleanup")
            let aiCleaner = useEnhancedCleanup ? try? await serviceContainer.aiCleanupService : nil

            let sectionDataList = await Task.detached(priority: .userInitiated) {
                [cleaner, detector, workingPages, outline, aiCleaner] in
                var cleanedPages = cleaner.cleanPages(workingPages)
                // Enhanced (on-device NLP) pass runs per page, on top of the deterministic
                // clean, and falls back silently to the deterministic result on any failure —
                // exactly the validate-or-fall-back contract CLAUDE.md specifies.
                if let aiCleaner {
                    var enhanced: [PageText] = []
                    for page in cleanedPages {
                        if let improved = await aiCleaner.runCleanup(on: page.text) {
                            enhanced.append(PageText(pageNumber: page.pageNumber, text: improved))
                        } else {
                            enhanced.append(page)
                        }
                    }
                    cleanedPages = enhanced
                }
                return detector.detect(pages: workingPages, outlineEntries: outline, cleanedPages: cleanedPages)
            }.value

            // Step 4 — persist sections on MainActor
            let sections: [SectionRecord] = sectionDataList.map { data in
                let s = SectionRecord(
                    title: data.title,
                    rawText: data.rawText,
                    order: data.order,
                    startPage: data.startPage,
                    endPage: data.endPage
                )
                s.cleanText = data.cleanText
                s.refreshWordCount()
                s.document = newRecord
                context.insert(s)
                return s
            }

            newRecord.sections         = sections
            newRecord.processingStatus = .ready
            try context.save()

            // Cache section data so re-processing (e.g. a future re-import or repair flow)
            // can skip straight to a warm result instead of re-running extraction/cleanup.
            await cache.cacheSectionData(sectionDataList, for: newRecord.id)

        } catch let err as ImportError {
            fail(record: record, message: err.localizedDescription, context: context)
        } catch {
            fail(record: record, message: "Processing failed: \(error.localizedDescription)", context: context)
        }
        if let record {
            processingDocumentIds.remove(record.id)
        }
    }

    private func fail(record: DocumentRecord?, message: String, context: ModelContext) {
        errorMessage = message
        if let record {
            record.processingStatus = .failed
            try? context.save()
        }
    }
}
