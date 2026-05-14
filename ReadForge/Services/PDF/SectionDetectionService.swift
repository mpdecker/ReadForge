import Foundation

struct SectionData: Sendable, Codable {
    let title: String
    let order: Int
    let startPage: Int
    let endPage: Int
    let rawText: String
}

struct PDFSectionDetectionService: Sendable {
    private let wordsPerChunk = 3_000

    func detect(
        pages: [PageText],
        outlineEntries: [(title: String, pageIndex: Int)],
        cleanedText: String
    ) -> [SectionData] {
        if !outlineEntries.isEmpty {
            return fromOutline(outlineEntries, pages: pages)
        }
        return fromHeuristics(cleanedText: cleanedText)
    }

    private func fromOutline(
        _ entries: [(title: String, pageIndex: Int)],
        pages: [PageText]
    ) -> [SectionData] {
        guard !pages.isEmpty else { return [] }
        let lastIdx = pages.count - 1

        // Filter out-of-range entries then sort
        let sorted = entries
            .filter { $0.pageIndex >= 0 && $0.pageIndex <= lastIdx }
            .sorted { $0.pageIndex < $1.pageIndex }

        guard !sorted.isEmpty else { return fromHeuristics(cleanedText: pages.map(\.text).joined(separator: "\n\n")) }

        return sorted.enumerated().map { i, entry in
            let start = entry.pageIndex
            let end = i + 1 < sorted.count ? max(start, sorted[i + 1].pageIndex - 1) : lastIdx
            let clampedEnd = min(end, lastIdx)
            let text = pages[start...clampedEnd].map(\.text).joined(separator: "\n\n")
            return SectionData(title: entry.title, order: i, startPage: start + 1, endPage: clampedEnd + 1, rawText: text)
        }
    }

    private func fromHeuristics(cleanedText: String) -> [SectionData] {
        guard !cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let paragraphs = cleanedText.components(separatedBy: "\n\n")
        var result: [SectionData] = []
        var buffer: [String] = []
        var wordCount = 0
        var pendingTitle: String?
        var order = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            result.append(SectionData(
                title: pendingTitle ?? "Section \(order + 1)",
                order: order,
                startPage: 1,
                endPage: 1,
                rawText: buffer.joined(separator: "\n\n")
            ))
            order += 1
            buffer = []
            wordCount = 0
            pendingTitle = nil
        }

        for para in paragraphs {
            let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if isHeading(trimmed) {
                if wordCount >= wordsPerChunk / 2 { flush() }
                pendingTitle = trimmed
            } else {
                buffer.append(trimmed)
                wordCount += trimmed.split(separator: " ").count
                if wordCount >= wordsPerChunk { flush() }
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
