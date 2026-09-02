import Foundation
import PDFKit
import Vision
import UIKit

/// On-device OCR fallback for scanned PDFs (Vision framework, per CLAUDE.md Phase 13/16).
/// Used when `PDFExtractionService.isLikelyScanned` reports a PDF has no usable text layer —
/// each page is rendered to an image and run through `VNRecognizeTextRequest` instead.
///
/// `nonisolated` (overriding this module's default MainActor isolation): every method here is
/// pure Vision/PDFKit computation with no actor affinity, meant to run off the main thread (this
/// is always invoked from a background `Task.detached` — see `LibraryViewModel`). Only the
/// top-level `recognizeText(from:)` was previously marked `nonisolated`; its own private helpers
/// (`recognizeText(on:)`, `rasterize(_:)`) were not, so calling them was already a real
/// actor-isolation mismatch (a compiler warning: "call to main actor-isolated instance method...
/// in a synchronous nonisolated context"), not just missing annotation noise.
nonisolated struct OCRService: Sendable {
    enum OCRError: LocalizedError {
        case cannotOpen
        case noPages
        /// Vision itself threw/failed to produce results on this many pages (not merely pages
        /// with little text, which can legitimately happen) — thrown instead of silently
        /// returning incomplete text so the caller can surface it rather than shipping a
        /// document permanently missing a chunk of its content with no error shown anywhere.
        case partialFailure(failedPageCount: Int, totalPageCount: Int)

        var errorDescription: String? {
            switch self {
            case .cannotOpen: return "The PDF could not be opened for OCR."
            case .noPages:    return "The document has no pages to scan."
            case .partialFailure(let failed, let total):
                return "Text recognition failed on \(failed) of \(total) pages."
            }
        }
    }

    /// Renders every page of the PDF and runs on-device text recognition over each one.
    /// Runs entirely locally — no network access, per CLAUDE.md's privacy rules.
    nonisolated func recognizeText(from fileURL: URL) throws -> [PageText] {
        guard let pdf = PDFDocument(url: fileURL) else { throw OCRError.cannotOpen }
        guard pdf.pageCount > 0 else { throw OCRError.noPages }

        var pages: [PageText] = []
        var failedPageCount = 0
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { continue }
            let text: String
            do {
                text = try recognizeText(on: page)
            } catch {
                // Previously swallowed via `try?` with no signal at all — a batch of pages that
                // genuinely failed recognition (not just pages with little text) could hide
                // behind a document-wide average that still cleared the "needs OCR" threshold,
                // silently shipping a document permanently missing that chunk of content.
                ReadForgeLogger.error(
                    category: "OCR", message: "Text recognition failed on page \(index + 1)", error: error
                )
                failedPageCount += 1
                text = ""
            }
            pages.append(PageText(pageNumber: index + 1, text: text))
        }
        // Only counts pages where Vision itself threw — not pages that simply produced little
        // text, which is a normal, legitimate outcome for a mostly-blank or image-only page.
        guard failedPageCount == 0 || failedPageCount * 10 < pdf.pageCount else {
            throw OCRError.partialFailure(failedPageCount: failedPageCount, totalPageCount: pdf.pageCount)
        }
        return pages
    }

    // MARK: - Private

    private func recognizeText(on page: PDFPage) throws -> String {
        guard let cgImage = rasterize(page) else { return "" }

        var recognizedLines: [String] = []
        var recognitionError: Error?
        let request = VNRecognizeTextRequest { request, error in
            if let error {
                recognitionError = error
                return
            }
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            recognizedLines = Self.orderedLines(from: observations)
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        if let recognitionError { throw recognitionError }

        return recognizedLines.joined(separator: "\n")
    }

    /// Vision returns text observations in roughly top-to-bottom scan order across the FULL
    /// image width, with no awareness of multi-column layout — joining them as-is on a
    /// two-column page (common in academic papers, newspapers) interleaves left- and
    /// right-column lines by vertical position, producing nonsensical reading order. This is a
    /// heuristic, not full layout analysis: it looks for one clear horizontal gap that splits the
    /// observations roughly evenly and, if found, treats it as a two-column boundary — reading
    /// the left column top-to-bottom, then the right column top-to-bottom. Anything that doesn't
    /// look like a confident two-column split (single-column pages, ragged/irregular layouts)
    /// falls back to a plain top-to-bottom reading, which is what the code did before.
    private static func orderedLines(from observations: [VNRecognizedTextObservation]) -> [String] {
        guard observations.count > 4 else {
            // Vision's `boundingBox` origin is bottom-left, normalized 0...1, so larger y is
            // higher up the page — descending y is top-to-bottom reading order.
            return observations
                .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                .compactMap { $0.topCandidates(1).first?.string }
        }

        let sortedByX = observations.sorted { $0.boundingBox.midX < $1.boundingBox.midX }
        var widestGap: (index: Int, size: CGFloat) = (0, 0)
        for i in 1..<sortedByX.count {
            let gap = sortedByX[i].boundingBox.midX - sortedByX[i - 1].boundingBox.midX
            if gap > widestGap.size { widestGap = (i, gap) }
        }

        let left = sortedByX[..<widestGap.index]
        let right = sortedByX[widestGap.index...]
        // Require a real gap (not just noise) and a roughly balanced split — an outlier line
        // (e.g. one indented caption) shouldn't get misread as a whole second column.
        let isConfidentColumnSplit = widestGap.size > 0.1
            && min(left.count, right.count) >= observations.count / 4

        guard isConfidentColumnSplit else {
            return observations
                .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                .compactMap { $0.topCandidates(1).first?.string }
        }

        return [left, right].flatMap { column in
            column
                .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                .compactMap { $0.topCandidates(1).first?.string }
        }
    }

    /// Renders a PDF page to a white-backed raster image at 2x for legible small print,
    /// without the memory blowup of rendering at extreme resolution.
    private func rasterize(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        // `page.bounds(for:)` returns the raw, unrotated media box — it never consults
        // `page.rotation` (90°/270° is common from mobile-scanning apps that keep a portrait
        // mediaBox but flag individual pages `/Rotate 90`). Without swapping the canvas
        // dimensions to match, `PDFPage.draw(with:to:)` still draws the rotated content into a
        // canvas sized for the wrong orientation, producing a squished/clipped raster that Vision
        // then OCRs into garbled or truncated text.
        let isSideways = page.rotation == 90 || page.rotation == 270
        let scale: CGFloat = 2.0
        let size = isSideways
            ? CGSize(width: bounds.height * scale, height: bounds.width * scale)
            : CGSize(width: bounds.width * scale, height: bounds.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 // we've already applied `scale` to `size`
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let image = renderer.image { context in
            UIColor.white.set()
            context.fill(CGRect(origin: .zero, size: size))

            let cgContext = context.cgContext
            cgContext.translateBy(x: 0, y: size.height)
            cgContext.scaleBy(x: scale, y: -scale)
            // `PDFPage.draw(with:to:)` already applies the page's own rotation internally when
            // drawing into `.mediaBox` — only the destination canvas's dimensions needed fixing.
            page.draw(with: .mediaBox, to: cgContext)
        }

        return image.cgImage
    }
}
