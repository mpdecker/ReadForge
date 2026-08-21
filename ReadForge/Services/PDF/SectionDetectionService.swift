import Foundation

struct SectionData: Sendable, Codable {
    let title: String
    let order: Int
    let startPage: Int
    let endPage: Int
    let rawText: String
    let cleanText: String
}

// Explicit conformance is required here: `ServiceContainer.createDefaultInstance` resolves this
// type via `PDFSectionDetectionService() as? T` where `T == SectionDetectionService`, and Swift's
// protocol conformance is nominal — without this, that cast silently returns nil, `resolve(...)`
// throws `.serviceNotFound`, and every real import through `LibraryViewModel` fails immediately.
struct PDFSectionDetectionService: Sendable, SectionDetectionService {
    private let wordsPerChunk = 3_000

    /// - Parameter cleanedPages: output of `TextCleanupService.cleanPages(_:)`, kept aligned by
    ///   page number with `pages` so both raw and cleaned text can be recovered per section.
    func detect(
        pages: [PageText],
        outlineEntries: [(title: String, pageIndex: Int)],
        cleanedPages: [PageText]
    ) -> [SectionData] {
        if !outlineEntries.isEmpty {
            return fromOutline(outlineEntries, pages: pages, cleanedPages: cleanedPages)
        }
        return fromHeuristics(pages: pages, cleanedPages: cleanedPages)
    }

    private func fromOutline(
        _ entries: [(title: String, pageIndex: Int)],
        pages: [PageText],
        cleanedPages: [PageText]
    ) -> [SectionData] {
        guard !pages.isEmpty else { return [] }
        let lastIdx = pages.count - 1

        // Filter out-of-range entries then sort
        let sorted = entries
            .filter { $0.pageIndex >= 0 && $0.pageIndex <= lastIdx }
            .sorted { $0.pageIndex < $1.pageIndex }

        guard !sorted.isEmpty else {
            return fromHeuristics(pages: pages, cleanedPages: cleanedPages)
        }

        let cleanedByNumber = Dictionary(uniqueKeysWithValues: cleanedPages.map { ($0.pageNumber, $0.text) })

        return sorted.enumerated().map { i, entry in
            let start = entry.pageIndex
            let end = i + 1 < sorted.count ? max(start, sorted[i + 1].pageIndex - 1) : lastIdx
            let clampedEnd = min(end, lastIdx)
            let rawText = pages[start...clampedEnd].map(\.text).joined(separator: "\n\n")
            let cleanText = pages[start...clampedEnd]
                .compactMap { cleanedByNumber[$0.pageNumber] }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            return SectionData(
                title: entry.title,
                order: i,
                startPage: start + 1,
                endPage: clampedEnd + 1,
                rawText: rawText,
                // Cleanup can legitimately empty out a page (e.g. an all-header/footer page);
                // only fall back to raw text if cleanup produced nothing at all for the range.
                cleanText: cleanText.isEmpty ? rawText : cleanText
            )
        }
    }

    private func fromHeuristics(pages: [PageText], cleanedPages: [PageText]) -> [SectionData] {
        let nonEmptyCleaned = cleanedPages.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonEmptyCleaned.isEmpty else { return [] }

        let rawByNumber = Dictionary(uniqueKeysWithValues: pages.map { ($0.pageNumber, $0.text) })

        var result: [SectionData] = []
        var buffer: [String] = []
        var wordCount = 0
        var pendingTitle: String?
        var order = 0
        var startPage: Int?
        var endPage: Int?

        func flush() {
            guard !buffer.isEmpty, let start = startPage, let end = endPage else { return }
            let cleanText = buffer.joined(separator: "\n\n")
            let rawText = (start...end)
                .compactMap { rawByNumber[$0] }
                .joined(separator: "\n\n")
            result.append(SectionData(
                title: pendingTitle ?? "Section \(order + 1)",
                order: order,
                startPage: start,
                endPage: end,
                rawText: rawText.isEmpty ? cleanText : rawText,
                cleanText: cleanText
            ))
            order += 1
            buffer = []
            wordCount = 0
            pendingTitle = nil
            startPage = nil
            endPage = nil
        }

        for page in nonEmptyCleaned {
            let paragraphs = page.text.components(separatedBy: "\n\n")
            for para in paragraphs {
                let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                if isHeading(trimmed) {
                    if wordCount >= wordsPerChunk / 2 { flush() }
                    pendingTitle = trimmed
                } else {
                    buffer.append(trimmed)
                    wordCount += trimmed.split(separator: " ").count
                    startPage = startPage ?? page.pageNumber
                    endPage = page.pageNumber
                    if wordCount >= wordsPerChunk { flush() }
                }
            }
        }
        flush()
        return result
    }

    // Short, no trailing period, title-case or all-caps, ≤10 words.
    func isHeading(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard (2...80).contains(t.count), !t.hasSuffix("."), !t.hasSuffix("?") else { return false }
        let words = t.split(separator: " ")
        guard words.count <= 10 else { return false }
        let allCaps = t == t.uppercased() && t.contains(where: \.isLetter)
        let titleCase = words.allSatisfy { $0.first?.isUppercase == true }
        return allCaps || titleCase
    }
}
