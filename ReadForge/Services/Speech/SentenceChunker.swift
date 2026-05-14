import Foundation
import NaturalLanguage

struct SentenceChunker {
    private let minLength = 300
    private let maxLength = 800

    func chunk(_ text: String) -> [String] {
        var sentences: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespaces)
            if !sentence.isEmpty { sentences.append(sentence) }
            return true
        }
        return merge(sentences)
    }

    // Combine short sentences up to maxLength; split anything over maxLength at word boundaries.
    private func merge(_ sentences: [String]) -> [String] {
        var chunks: [String] = []
        var current = ""

        for sentence in sentences {
            if current.isEmpty {
                current = sentence
            } else if current.count + 1 + sentence.count <= maxLength {
                current += " " + sentence
            } else {
                if current.count >= minLength {
                    chunks.append(current)
                    current = sentence
                } else {
                    current += " " + sentence
                    if current.count >= minLength {
                        chunks.append(current)
                        current = ""
                    }
                }
            }
        }

        if !current.isEmpty { chunks.append(current) }

        // Hard-split any chunk still over maxLength at a word boundary
        return chunks.flatMap { hardSplit($0) }
    }

    private func hardSplit(_ text: String) -> [String] {
        guard text.count > maxLength else { return [text] }
        var result: [String] = []
        var remaining = text
        while remaining.count > maxLength {
            let cutIndex = remaining.index(remaining.startIndex, offsetBy: maxLength)
            if let spaceIndex = remaining[..<cutIndex].lastIndex(of: " ") {
                result.append(String(remaining[..<spaceIndex]))
                remaining = String(remaining[remaining.index(after: spaceIndex)...])
            } else {
                result.append(String(remaining.prefix(maxLength)))
                remaining = String(remaining.dropFirst(maxLength))
            }
        }
        if !remaining.isEmpty { result.append(remaining) }
        return result
    }
}
