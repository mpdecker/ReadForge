import Foundation

/// Format-agnostic document metadata returned by all extractors.
struct DocumentMetadata: Sendable {
    let title: String?
    let author: String?
    let subject: String?
    let pageCount: Int
}

/// Unified extraction contract that every format-specific service satisfies.
protocol DocumentExtracting: Sendable {
    /// Extract pages of raw text in reading order.
    func extractPages(from url: URL) throws -> [PageText]

    /// Extract document-level metadata. Never throws; returns empty metadata on failure.
    func extractMetadata(from url: URL) -> DocumentMetadata

    /// Return a flat (title, pageIndex) table of contents / outline. Empty if not available.
    func outline(from url: URL) -> [(title: String, pageIndex: Int)]

    /// Return true if the document appears to be a scanned image with no selectable text.
    func isLikelyScanned(_ pages: [PageText]) -> Bool
}

extension DocumentExtracting {
    /// Default: non-PDF formats never require OCR.
    func isLikelyScanned(_ pages: [PageText]) -> Bool { false }

    /// Default: no outline available.
    func outline(from url: URL) -> [(title: String, pageIndex: Int)] { [] }
}
