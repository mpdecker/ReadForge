package com.readforge.app.pdf

import com.readforge.app.models.PageText

/** Deterministic cleanup matching the iOS TextCleanupService rules. */
object TextCleanupService {

    private val citationRegex = Regex("""\[\d+(?:[,\-]\d+)*\]""")

    fun clean(pages: List<PageText>): String {
        if (pages.isEmpty()) return ""

        val normalised = pages.map { PageText(it.pageNumber, normaliseCrlf(it.text)) }
        val repeated = repeatedLines(normalised)

        return normalised
            .map { removingRepeated(it.text, repeated) }
            .joinToString("\n\n")
            .split("\n\n")
            .map { cleanParagraph(it) }
            .filter { it.isNotEmpty() }
            .joinToString("\n\n")
    }

    private fun repeatedLines(pages: List<PageText>): Set<String> {
        if (pages.size <= 3) return emptySet()
        val counts = mutableMapOf<String, Int>()
        for (page in pages) {
            val lines = page.text.split("\n")
            val candidates = lines.take(2) + lines.takeLast(2)
            for (line in candidates) {
                val t = line.trim()
                if (t.isEmpty()) continue
                counts[t] = (counts[t] ?: 0) + 1
            }
        }
        val threshold = maxOf(2, (pages.size * 0.3).toInt())
        return counts.filter { it.value >= threshold }.keys.toSet()
    }

    private fun removingRepeated(text: String, repeated: Set<String>): String =
        text.split("\n")
            .filter { line -> !repeated.contains(line.trim()) }
            .joinToString("\n")

    private fun cleanParagraph(text: String): String {
        var s = text
        s = s.replace("-\n", "")
        s = s.replace("\n", " ")
        s = citationRegex.replace(s, "")
        s = s.split(" ").filter { it.isNotEmpty() }.joinToString(" ")
        return s.trim()
    }

    private fun normaliseCrlf(text: String): String =
        text.replace("\r\n", "\n").replace("\r", "\n")
}
