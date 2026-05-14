import Foundation
import PDFKit

// PDFMetadata kept as a typealias so existing call sites compile without changes.
typealias PDFMetadata = DocumentMetadata

struct PDFExtractionService: Sendable, DocumentExtracting {
    enum ExtractionError: LocalizedError {
        case cannotOpen, passwordProtected, noPages

        var errorDescription: String? {
            switch self {
            case .cannotOpen:         return "The PDF could not be opened."
            case .passwordProtected:  return "Password-protected PDFs are not yet supported."
            case .noPages:            return "The PDF contains no readable pages."
            }
        }
    }

    nonisolated func extractPages(from fileURL: URL) throws -> [PageText] {
        guard let pdf = PDFDocument(url: fileURL) else { throw ExtractionError.cannotOpen }
        guard !pdf.isLocked else { throw ExtractionError.passwordProtected }
        guard pdf.pageCount > 0 else { throw ExtractionError.noPages }

        return (0..<pdf.pageCount).compactMap { index -> PageText? in
            guard let page = pdf.page(at: index) else { return nil }
            let text = page.string ?? ""
            return PageText(pageNumber: index + 1, text: text)
        }
    }

    nonisolated func extractMetadata(from fileURL: URL) -> DocumentMetadata {
        guard let pdf = PDFDocument(url: fileURL) else {
            return DocumentMetadata(title: nil, author: nil, subject: nil, pageCount: 0)
        }
        let attrs = pdf.documentAttributes
        return DocumentMetadata(
            title:     attrs?[PDFDocumentAttribute.titleAttribute]   as? String,
            author:    attrs?[PDFDocumentAttribute.authorAttribute]  as? String,
            subject:   attrs?[PDFDocumentAttribute.subjectAttribute] as? String,
            pageCount: pdf.pageCount
        )
    }

    nonisolated func outline(from fileURL: URL) -> [(title: String, pageIndex: Int)] {
        guard let pdf = PDFDocument(url: fileURL),
              let root = pdf.outlineRoot else { return [] }
        return flattenOutline(root, in: pdf, depth: 0)
    }

    private func flattenOutline(
        _ item: PDFOutline,
        in pdf: PDFDocument,
        depth: Int
    ) -> [(title: String, pageIndex: Int)] {
        var results: [(String, Int)] = []
        // Limit depth to avoid exploding micro-sections from deeply nested outlines
        if depth < 3,
           let dest = item.destination,
           let page = dest.page,
           let label = item.label, !label.trimmingCharacters(in: .whitespaces).isEmpty {
            results.append((label.trimmingCharacters(in: .whitespaces), pdf.index(for: page)))
        }
        for i in 0..<item.numberOfChildren {
            if let child = item.child(at: i) {
                results += flattenOutline(child, in: pdf, depth: depth + 1)
            }
        }
        return results
    }

    // Returns true when the PDF appears to be a scanned image (< 50 chars/page average).
    nonisolated func isLikelyScanned(_ pages: [PageText]) -> Bool {
        guard !pages.isEmpty else { return false }
        let totalChars = pages.reduce(0) { $0 + $1.text.count }
        return totalChars / pages.count < 50
    }
}
