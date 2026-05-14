import SwiftUI
import SwiftData
import Combine

@Observable
@MainActor
final class LibraryViewModel {
    var showImporter = false
    var errorMessage: String?
    var processingDocumentId: UUID?

    private let serviceContainer = ServiceContainer.shared

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
            
            // Validate format before touching the file system
            guard let format = DocumentFormat(url: url) else {
                throw ImportError.unsupportedFormat
            }

            // Step 1 — copy file, create record
            let newRecord = try importer.importDocument(from: url)
            context.insert(newRecord)
            try context.save()
            record = newRecord
            processingDocumentId = newRecord.id

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

            if extractor.isLikelyScanned(pages) {
                newRecord.processingStatus = .needsOCR
                try context.save()
                processingDocumentId = nil
                return
            }

            // Step 3 — clean + detect sections (background)
            newRecord.processingStatus = .cleaning
            try context.save()

            let outline = await Task.detached(priority: .userInitiated) {
                [extractor, fileURL] in
                extractor.outline(from: fileURL)
            }.value

            let sectionDataList = await Task.detached(priority: .userInitiated) {
                [cleaner, detector, pages, outline] in
                let cleaned = cleaner.clean(pages)
                return detector.detect(pages: pages, outlineEntries: outline, cleanedText: cleaned)
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
                s.document = newRecord
                context.insert(s)
                return s
            }

            newRecord.sections         = sections
            newRecord.processingStatus = .ready
            try context.save()

        } catch let err as ImportError {
            fail(record: record, message: err.localizedDescription, context: context)
        } catch {
            fail(record: record, message: "Processing failed: \(error.localizedDescription)", context: context)
        }
        processingDocumentId = nil
    }

    private func fail(record: DocumentRecord?, message: String, context: ModelContext) {
        errorMessage = message
        if let record {
            record.processingStatus = .failed
            try? context.save()
        }
    }
}
