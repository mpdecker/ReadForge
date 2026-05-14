import Foundation
import UIKit   // NSAttributedString document types (.rtf, .html) live in UIKit on iOS

/// Extracts text from plain-text formats: .txt, .rtf / .rtfd, and .html / .htm.
struct PlainTextExtractionService: Sendable, DocumentExtracting {

    // MARK: - DocumentExtracting

    nonisolated func extractPages(from url: URL) throws -> [PageText] {
        let text = try extractString(from: url)
        return splitIntoPages(text)
    }

    nonisolated func extractMetadata(from url: URL) -> DocumentMetadata {
        let raw   = url.deletingPathExtension().lastPathComponent
        let title = (raw.removingPercentEncoding ?? raw)
        return DocumentMetadata(title: title.isEmpty ? nil : title,
                                author: nil, subject: nil, pageCount: 0)
    }

    // outline & isLikelyScanned use protocol-extension defaults ([] / false).

    // MARK: - Private

    private func extractString(from url: URL) throws -> String {
        switch url.pathExtension.lowercased() {
        case "txt", "text": return try readPlainText(url)
        case "rtf", "rtfd": return try readRich(url, type: .rtf)
        case "html", "htm": return try readRich(url, type: .html)
        default:            return try readPlainText(url)
        }
    }

    private func readPlainText(_ url: URL) throws -> String {
        if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        return try String(contentsOf: url, encoding: .isoLatin1)
    }

    /// Uses NSAttributedString for RTF/HTML parsing.
    /// Thread-safe on iOS 15+; our minimum is iOS 17.
    private func readRich(_ url: URL, type docType: NSAttributedString.DocumentType) throws -> String {
        let data = try Data(contentsOf: url)
        var outAttrs: NSDictionary?
        let attr = try NSAttributedString(
            data: data,
            options: [
                .documentType:      docType,
                .characterEncoding: String.Encoding.utf8.rawValue as AnyObject
            ],
            documentAttributes: &outAttrs
        )
        return attr.string
    }

    /// Splits a long text string into ~3 000-character "pages" (word-boundary aligned)
    /// so the existing `TextCleanupService` + `SectionDetectionService` pipeline works
    /// with the same `[PageText]` contract it receives from PDF extraction.
    private func splitIntoPages(_ text: String, charsPerPage: Int = 3_000) -> [PageText] {
        guard !text.isEmpty else { return [] }
        var pages: [PageText] = []
        var index = text.startIndex
        var pageNumber = 1

        while index < text.endIndex {
            let rawEnd = text.index(index, offsetBy: charsPerPage, limitedBy: text.endIndex)
                         ?? text.endIndex
            let end = snapToWordBoundary(in: text, before: rawEnd)
            let chunk = String(text[index..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                pages.append(PageText(pageNumber: pageNumber, text: chunk))
                pageNumber += 1
            }
            index = end
        }
        return pages
    }

    private func snapToWordBoundary(in text: String, before end: String.Index) -> String.Index {
        guard end < text.endIndex else { return end }
        let lookback = min(60, text.distance(from: text.startIndex, to: end))
        let searchStart = text.index(end, offsetBy: -lookback)
        if let spaceIdx = text[searchStart..<end].lastIndex(where: \.isWhitespace) {
            return text.index(after: spaceIdx)
        }
        return end
    }
}
