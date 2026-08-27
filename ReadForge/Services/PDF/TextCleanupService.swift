import Foundation

struct PageText: Sendable {
    let pageNumber: Int
    let text: String
}

struct TextCleanupService: Sendable {
    // Pre-compiled regex for inline citation markers: [1], [1,2], [1-3]
    private static let citationRegex = try? NSRegularExpression(pattern: #"\[\d+(?:[,\-]\d+)*\]"#)

    func clean(_ pages: [PageText]) -> String {
        cleanPages(pages)
            .map(\.text)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// Same cleanup as `clean(_:)`, but keeps each page's cleaned text separate (with its
    /// original page number) instead of flattening to one string. Callers that need to know
    /// which page a piece of cleaned text came from — e.g. section detection, so it can report
    /// accurate page ranges — should use this instead of `clean(_:)`.
    func cleanPages(_ pages: [PageText]) -> [PageText] {
        guard !pages.isEmpty else { return [] }

        let normalised = pages.map { PageText(pageNumber: $0.pageNumber, text: normaliseCRLF($0.text)) }
        let repeated = repeatedLines(in: normalised)

        return normalised.map { page in
            let stripped = removingRepeated(from: page.text, lines: repeated)
            let cleaned = stripped
                .components(separatedBy: "\n\n")
                .map { cleanParagraph($0) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            return PageText(pageNumber: page.pageNumber, text: cleaned)
        }
    }

    // Collect first/last 2 lines per page; anything on ≥30% of pages is a header/footer.
    private func repeatedLines(in pages: [PageText]) -> Set<String> {
        guard pages.count > 3 else { return [] }
        var counts: [String: Int] = [:]
        for page in pages {
            let lines = page.text.components(separatedBy: "\n")
            let candidates = Array(lines.prefix(2)) + Array(lines.suffix(2))
            // Dedupe within the page first. On a short page (≤4 lines) the prefix(2)
            // and suffix(2) windows overlap, so a page's own unique line would otherwise
            // be counted twice from a single page — enough to cross the threshold below
            // on its own and get misclassified as a repeated header/footer.
            let uniqueOnPage = Set(
                candidates
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            )
            for line in uniqueOnPage {
                counts[line, default: 0] += 1
            }
        }
        // `.rounded(.up)` (ceiling), not `Int(...)` truncation: for e.g. 7 pages, `0.3 * 7 = 2.1`
        // truncated to `2` meant a line needed to appear on only 2/7 ≈ 28.6% of pages — below
        // the documented "30%+" rule — to be misclassified as a repeated header/footer and
        // stripped from every page it appeared on, including any that were legitimate,
        // non-boilerplate body text.
        let threshold = max(2, Int((Double(pages.count) * 0.3).rounded(.up)))
        return Set(counts.filter { $0.value >= threshold }.keys)
    }

    /// Removes a detected repeated line only from the leading/trailing window it was actually
    /// sampled from (`repeatedLines`'s first/last 2 lines per page) — the previous version
    /// matched and deleted a repeated line anywhere in the page's full text, so a running header
    /// (e.g. "CHAPTER THREE: THE JOURNEY") that also happened to appear as an ordinary
    /// mid-chapter line (a reused section-break title, a quoted heading) silently lost that
    /// legitimate body text too, not just the boilerplate copy.
    private func removingRepeated(from text: String, lines repeated: Set<String>) -> String {
        guard !repeated.isEmpty else { return text }
        var lines = text.components(separatedBy: "\n")
        let windowSize = 2
        let leadingRange = 0..<min(windowSize, lines.count)
        let trailingRange = max(leadingRange.upperBound, lines.count - windowSize)..<lines.count
        for range in [leadingRange, trailingRange] {
            for i in range where repeated.contains(lines[i].trimmingCharacters(in: .whitespaces)) {
                lines[i] = ""
            }
        }
        return lines.joined(separator: "\n")
    }

    private func cleanParagraph(_ text: String) -> String {
        var s = text
        // Fix hyphenated line breaks: "algo-\nrithm" → "algorithm". A plain "-\n" substring
        // match missed the common case where PDFKit's extracted justified text has a trailing
        // space before the line break ("algo- \nrithm") — the regex form matches both.
        s = s.replacingOccurrences(of: "-[ \t]*\n", with: "", options: .regularExpression)
        // Join soft-wrapped lines within the paragraph
        s = s.replacingOccurrences(of: "\n", with: " ")
        // Remove inline square-bracket citations: [1], [1,2], [1-3]
        if let rx = Self.citationRegex {
            let range = NSRange(s.startIndex..., in: s)
            s = rx.stringByReplacingMatches(in: s, range: range, withTemplate: "")
        }
        // Collapse runs of spaces (O(n) via components)
        s = s.components(separatedBy: " ").filter { !$0.isEmpty }.joined(separator: " ")
        return s.trimmingCharacters(in: .whitespaces)
    }

    // Normalise Windows (\r\n) and old Mac (\r) line endings.
    private func normaliseCRLF(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
