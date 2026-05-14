import Foundation
import UniformTypeIdentifiers

/// Supported document formats for import and extraction.
enum DocumentFormat: String, Sendable, CaseIterable {
    case pdf
    case epub
    case txt
    case rtf
    case html

    /// Derive format from a URL's path extension.
    init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "pdf":          self = .pdf
        case "epub":         self = .epub
        case "txt", "text":  self = .txt
        case "rtf", "rtfd":  self = .rtf
        case "html", "htm":  self = .html
        default:             return nil
        }
    }

    /// The canonical file extension for this format.
    var fileExtension: String {
        switch self {
        case .pdf:  return "pdf"
        case .epub: return "epub"
        case .txt:  return "txt"
        case .rtf:  return "rtf"
        case .html: return "html"
        }
    }

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .pdf:  return "PDF"
        case .epub: return "EPUB"
        case .txt:  return "Plain Text"
        case .rtf:  return "Rich Text"
        case .html: return "HTML"
        }
    }

    /// UTTypes accepted by `fileImporter`. EPUB uses the IDPF UTI registered on iOS 14+.
    static var utTypes: [UTType] {
        var types: [UTType] = [.pdf, .plainText, .rtf, .html]
        if let epubType = UTType("org.idpf.epub-container") {
            types.insert(epubType, at: 1)
        }
        return types
    }
}
