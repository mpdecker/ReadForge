import Foundation

/// Routes a `DocumentFormat` to the appropriate extraction service.
/// All concrete extractors are value types and safe to share across tasks.
struct DocumentExtractionFactory: Sendable {
    private let pdf   = PDFExtractionService()
    private let epub  = EPUBExtractionService()
    private let plain = PlainTextExtractionService()

    func extractor(for format: DocumentFormat) -> any DocumentExtracting {
        switch format {
        case .pdf:          return pdf
        case .epub:         return epub
        case .txt, .rtf, .html: return plain
        }
    }
}
