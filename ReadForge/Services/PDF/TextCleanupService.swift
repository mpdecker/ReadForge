import Foundation

struct PageText: Sendable {
    let pageNumber: Int
    let text: String
}

struct TextCleanupService: Sendable {
    // Pre-compiled regex for inline citation markers: [1], [1,2], [1-3]
    private static let citationRegex = try? NSRegularExpression(pattern: #"\[\d+(?:[,\-]\d+)*\]"#)

    func clean(_ pages: [PageText]) -> String {
        guard !pages.isEmpty else { return "" }

        let normalised = pages.map { PageText(pageNumber: $0.pageNumber, text: normaliseCRLF($0.text)) }
        let repeated = repeatedLines(in: normalised)

        return normalised
            .map { removingRepeated(from: $0.text, lines: repeated) }
            .joined(separator: "\n\n")
            .components(separatedBy: "\n\n")
            .map { cleanParagraph($0) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    // Collect first/last 2 lines per page; anything on ≥30% of pages is a header/footer.
    private func repeatedLines(in pages: [PageText]) -> Set<String> {
        guard pages.count > 3 else { return [] }
        var counts: [String: Int] = [:]
        for page in pages {
            let lines = page.text.components(separatedBy: "\n")
            let candidates = Array(lines.prefix(2)) + Array(lines.suffix(2))
            for line in candidates {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty else { continue }
                counts[t, default: 0] += 1
            }
        }
        let threshold = max(2, Int(Double(pages.count) * 0.3))
        return Set(counts.filter { $0.value >= threshold }.keys)
    }

    private func removingRepeated(from text: String, lines repeated: Set<String>) -> String {
        text.components(separatedBy: "\n")
            .filter { !repeated.contains($0.trimmingCharacters(in: .whitespaces)) }
            .joined(separator: "\n")
    }

    private func cleanParagraph(_ text: String) -> String {
        var s = text
        // Fix hyphenated line breaks: "algo-\nrithm" → "algorithm"
        s = s.replacingOccurrences(of: "-\n", with: "")
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
