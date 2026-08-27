import Foundation
import PDFKit
import Vision
import UIKit

/// On-device OCR fallback for scanned PDFs (Vision framework, per CLAUDE.md Phase 13/16).
/// Used when `PDFExtractionService.isLikelyScanned` reports a PDF has no usable text layer —
/// each page is rendered to an image and run through `VNRecognizeTextRequest` instead.
struct OCRService: Sendable {
    enum OCRError: LocalizedError {
        case cannotOpen
        case noPages

        var errorDescription: String? {
            switch self {
            case .cannotOpen: return "The PDF could not be opened for OCR."
            case .noPages:    return "The document has no pages to scan."
            }
        }
    }

    /// Renders every page of the PDF and runs on-device text recognition over each one.
    /// Runs entirely locally — no network access, per CLAUDE.md's privacy rules.
    nonisolated func recognizeText(from fileURL: URL) throws -> [PageText] {
        guard let pdf = PDFDocument(url: fileURL) else { throw OCRError.cannotOpen }
        guard pdf.pageCount > 0 else { throw OCRError.noPages }

        var pages: [PageText] = []
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { continue }
            let text = (try? recognizeText(on: page)) ?? ""
            pages.append(PageText(pageNumber: index + 1, text: text))
        }
        return pages
    }

    // MARK: - Private

    private func recognizeText(on page: PDFPage) throws -> String {
        guard let cgImage = rasterize(page) else { return "" }

        var recognizedLines: [String] = []
        let request = VNRecognizeTextRequest { request, _ in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            recognizedLines = observations.compactMap { $0.topCandidates(1).first?.string }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        return recognizedLines.joined(separator: "\n")
    }

    /// Renders a PDF page to a white-backed raster image at 2x for legible small print,
    /// without the memory blowup of rendering at extreme resolution.
    private func rasterize(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let scale: CGFloat = 2.0
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 // we've already applied `scale` to `size`
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let image = renderer.image { context in
            UIColor.white.set()
            context.fill(CGRect(origin: .zero, size: size))

            let cgContext = context.cgContext
            cgContext.translateBy(x: 0, y: size.height)
            cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: cgContext)
        }

        return image.cgImage
    }
}
