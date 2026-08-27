import Foundation
import ZIPFoundation

/// Extracts text and metadata from EPUB 2/3 files.
/// EPUB is a ZIP archive containing XHTML content referenced by an OPF manifest.
struct EPUBExtractionService: Sendable, DocumentExtracting {

    // MARK: - DocumentExtracting

    nonisolated func extractPages(from url: URL) throws -> [PageText] {
        let archive = try openArchive(url)
        let opfPath = try findOPFPath(in: archive)
        let opfDir  = parentDirectory(of: opfPath)
        let (_,  spine) = try parseOPF(archive: archive, opfPath: opfPath, opfDir: opfDir)

        var pages: [PageText] = []
        for (index, href) in spine.enumerated() {
            // `href` is already percent-decoded (see `parseOPF`) so it matches the literal,
            // unencoded entry name ZIPFoundation stores — OPF manifest hrefs are XML attribute
            // values and, per the EPUB spec, spaces/non-ASCII characters in them are
            // percent-encoded (e.g. "chapter%2001.xhtml"), but the actual ZIP entry is named
            // literally ("chapter 01.xhtml"). Looking up the still-encoded href here previously
            // failed the archive subscript silently, dropping that entire chapter with no error.
            let fullPath = opfDir.isEmpty ? href : "\(opfDir)/\(href)"
            guard let entry = archive[fullPath] else { continue }
            let data = try extractData(entry, from: archive)
            let text = xhtmlToPlainText(data)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            pages.append(PageText(pageNumber: index + 1, text: text))
        }
        return pages
    }

    nonisolated func extractMetadata(from url: URL) -> DocumentMetadata {
        guard
            let archive = try? openArchive(url),
            let opfPath = try? findOPFPath(in: archive),
            let (meta, spine) = try? parseOPF(
                archive: archive, opfPath: opfPath,
                opfDir: parentDirectory(of: opfPath)
            )
        else {
            return DocumentMetadata(title: nil, author: nil, subject: nil, pageCount: 0)
        }
        return DocumentMetadata(title: meta.title, author: meta.author,
                                subject: nil, pageCount: spine.count)
    }

    nonisolated func outline(from url: URL) -> [(title: String, pageIndex: Int)] {
        guard
            let archive = try? openArchive(url),
            let opfPath = try? findOPFPath(in: archive)
        else { return [] }
        let opfDir = parentDirectory(of: opfPath)
        guard let (_, spine) = try? parseOPF(archive: archive, opfPath: opfPath, opfDir: opfDir)
        else { return [] }
        return buildTOC(archive: archive, opfDir: opfDir, spine: spine)
    }

    // isLikelyScanned: EPUBs always contain text — default false from protocol extension.

    // MARK: - Private: Archive helpers

    private func openArchive(_ url: URL) throws -> Archive {
        try Archive(url: url, accessMode: .read)
    }

    private func extractData(_ entry: Entry, from archive: Archive) throws -> Data {
        var data = Data()
        _ = try archive.extract(entry) { chunk in data.append(chunk) }
        return data
    }

    private func parentDirectory(of path: String) -> String {
        let components = path.components(separatedBy: "/")
        guard components.count > 1 else { return "" }
        return components.dropLast().joined(separator: "/")
    }

    // MARK: - Private: OPF location (META-INF/container.xml)

    private func findOPFPath(in archive: Archive) throws -> String {
        guard let entry = archive["META-INF/container.xml"] else {
            throw EPUBError.missingContainer
        }
        let data = try extractData(entry, from: archive)
        let parser = ContainerParser()
        XMLParser(data: data).withDelegate(parser).parse()
        guard let path = parser.opfPath else { throw EPUBError.missingOPF }
        return path
    }

    // MARK: - Private: OPF parsing (metadata + spine)

    private func parseOPF(
        archive: Archive, opfPath: String, opfDir: String
    ) throws -> (meta: OPFMeta, spine: [String]) {
        guard let entry = archive[opfPath] else { throw EPUBError.missingOPF }
        let data = try extractData(entry, from: archive)
        let parser = OPFParser()
        XMLParser(data: data).withDelegate(parser).parse()
        // Resolve spine item refs against manifest hrefs, percent-decoding each — see the
        // `extractPages` doc comment on why the raw attribute value can't be used directly as a
        // ZIP entry name.
        let hrefs = parser.spineIds.compactMap { parser.manifest[$0] }.map { $0.removingPercentEncoding ?? $0 }
        return (parser.meta, hrefs)
    }

    // MARK: - Private: TOC (NCX or fallback)

    private func buildTOC(
        archive: Archive, opfDir: String, spine: [String]
    ) -> [(title: String, pageIndex: Int)] {
        let ncxPath = opfDir.isEmpty ? "toc.ncx" : "\(opfDir)/toc.ncx"
        if let entry = archive[ncxPath],
           let data = try? extractData(entry, from: archive) {
            let parser = NCXParser(spine: spine)
            XMLParser(data: data).withDelegate(parser).parse()
            if !parser.result.isEmpty { return parser.result }
        }
        // Fallback: label each spine item generically
        return spine.enumerated().map { ("Chapter \($0.offset + 1)", $0.offset) }
    }

    // MARK: - Private: HTML → plain text (thread-safe, no NSAttributedString)

    private func xhtmlToPlainText(_ data: Data) -> String {
        guard var text = String(data: data, encoding: .utf8)
                      ?? String(data: data, encoding: .isoLatin1) else { return "" }

        // Strip <script>/<style>/<head> blocks — TAG AND CONTENT together — before the generic
        // tag-strip below, which only removes markup, not the text between tags. Per-chapter
        // inline CSS (`<style>body{...}</style>` inside <head>) is extremely common in EPUB, and
        // without this its raw CSS/JS text was left in place and prepended verbatim to the
        // narrated chapter.
        for tag in ["script", "style", "head"] {
            text = text.replacingOccurrences(
                of: "(?is)<\(tag)\\b[^>]*>.*?</\(tag)>",
                with: "", options: .regularExpression
            )
        }

        // Block-level elements → paragraph breaks
        text = text.replacingOccurrences(
            of: #"<(?:p|div|br|h[1-6])(?:\s[^>]*)?\s*/?>"#,
            with: "\n", options: .regularExpression
        )
        // Strip all remaining tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode common HTML entities
        text = decodeHTMLEntities(text)
        // Collapse runs of spaces; normalise excessive blank lines
        text = text.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeHTMLEntities(_ text: String) -> String {
        var s = text
        let entities: KeyValuePairs<String, String> = [
            "&amp;": "&",  "&lt;": "<",  "&gt;": ">",
            "&quot;": "\"", "&apos;": "'", "&nbsp;": " ",
            "&#160;": " ", "&#8212;": "—", "&#8211;": "–",
            "&#8216;": "\u{2018}", "&#8217;": "\u{2019}",
            "&#8220;": "\u{201C}", "&#8221;": "\u{201D}",
        ]
        for (entity, char) in entities {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        // Numeric decimal entities &#NNN;
        if let rx = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let ns = s as NSString
            var offset = 0
            for match in rx.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
                let full  = match.range(at: 0)
                let inner = match.range(at: 1)
                if let scalar = UInt32(ns.substring(with: inner)).flatMap(Unicode.Scalar.init) {
                    s = (s as NSString).replacingCharacters(
                        in: NSRange(location: full.location + offset, length: full.length),
                        with: String(scalar)
                    )
                }
            }
            _ = offset // suppress unused warning
        }
        return s
    }

    // MARK: - Errors & value types

    enum EPUBError: LocalizedError {
        case missingContainer, missingOPF
        var errorDescription: String? {
            "The EPUB file is missing required metadata and cannot be opened."
        }
    }

    struct OPFMeta {
        var title: String?
        var author: String?
    }
}

// MARK: - XMLParser convenience

private extension XMLParser {
    @discardableResult
    func withDelegate(_ delegate: XMLParserDelegate) -> XMLParser {
        self.delegate = delegate
        return self
    }
}

// MARK: - container.xml parser  →  finds OPF rootfile path

private final class ContainerParser: NSObject, XMLParserDelegate {
    var opfPath: String?

    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        if (element == "rootfile" || element.hasSuffix(":rootfile")), opfPath == nil {
            opfPath = attributes["full-path"]
        }
    }
}

// MARK: - OPF parser  →  metadata + manifest + spine

private final class OPFParser: NSObject, XMLParserDelegate {
    var meta = EPUBExtractionService.OPFMeta()
    /// manifest id → relative href (only xhtml/html items)
    var manifest: [String: String] = [:]
    /// ordered spine item idrefs
    var spineIds: [String] = []

    private var currentText = ""
    private var captureNext: CaptureTarget = .none

    private enum CaptureTarget { case none, title, creator }

    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        currentText = ""
        let localName = element.components(separatedBy: ":").last ?? element
        switch localName {
        case "title":   captureNext = meta.title   == nil ? .title   : .none
        case "creator": captureNext = meta.author  == nil ? .creator : .none
        case "item":
            if let id = attributes["id"],
               let href = attributes["href"],
               let mt = attributes["media-type"],
               mt.contains("xhtml") || mt.contains("html") {
                manifest[id] = href
            }
        case "itemref":
            if let idref = attributes["idref"] { spineIds.append(idref) }
        default: captureNext = .none
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement element: String,
                namespaceURI: String?, qualifiedName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch captureNext {
        case .title   where !text.isEmpty: meta.title  = text
        case .creator where !text.isEmpty: meta.author = text
        default: break
        }
        captureNext = .none
        currentText = ""
    }
}

// MARK: - NCX (toc.ncx) parser  →  table of contents

private final class NCXParser: NSObject, XMLParserDelegate {
    private let spine: [String]
    private(set) var result: [(title: String, pageIndex: Int)] = []

    private var inNavLabel = false
    private var pendingTitle = ""
    private var pendingContent = ""
    private var currentText = ""

    init(spine: [String]) { self.spine = spine }

    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        let localName = element.components(separatedBy: ":").last ?? element
        switch localName {
        case "navPoint":  pendingTitle = ""; pendingContent = ""
        case "navLabel":  inNavLabel = true
        case "text":      currentText = ""
        case "content":
            // src may be "chapter1.xhtml" or "OEBPS/chapter1.xhtml#anchor" — percent-decoded for
            // the same reason as the OPF manifest hrefs (see `parseOPF`), and so it lines up with
            // `spine`'s now-decoded entries for the exact-path match below.
            if let src = attributes["src"] {
                let withoutAnchor = src.components(separatedBy: "#").first ?? src
                pendingContent = withoutAnchor.removingPercentEncoding ?? withoutAnchor
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement element: String,
                namespaceURI: String?, qualifiedName: String?) {
        let localName = element.components(separatedBy: ":").last ?? element
        switch localName {
        case "text" where inNavLabel:
            pendingTitle = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        case "navLabel":
            inNavLabel = false
        case "navPoint":
            // Match content href to the spine to get a page index. Tries the exact relative
            // path first — a filename-only match (the old sole behavior) misattributes the TOC
            // entry when two spine files share a filename in different subdirectories (e.g. a
            // multi-language EPUB with "en/chapter1.xhtml" and "fr/chapter1.xhtml"), always
            // resolving to whichever is `firstIndex`-matched regardless of which one the NCX
            // entry actually pointed at. Falling back to filename-only only when no exact path
            // matches keeps the previous behavior for archives whose NCX `src` is based
            // differently than the OPF manifest's hrefs (e.g. missing/extra directory prefix).
            let idx = spine.firstIndex(of: pendingContent) ?? spine.firstIndex {
                ($0 as NSString).lastPathComponent == (pendingContent as NSString).lastPathComponent
            }
            if let idx, !pendingTitle.isEmpty {
                result.append((pendingTitle, idx))
            }
        default: break
        }
        currentText = ""
    }
}
