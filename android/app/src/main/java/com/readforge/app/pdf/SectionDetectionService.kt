package com.readforge.app.pdf

import com.readforge.app.models.OutlineEntry
import com.readforge.app.models.PageText
import com.readforge.app.models.SectionData

/** Section splitting matching the iOS PDFSectionDetectionService (outline optional, else heuristics). */
object SectionDetectionService {

    private const val WORDS_PER_CHUNK = 3_000

    fun detect(
        pages: List<PageText>,
        outlineEntries: List<OutlineEntry>,
        cleanedText: String,
    ): List<SectionData> {
        if (outlineEntries.isNotEmpty()) {
            return fromOutline(outlineEntries, pages)
        }
        return fromHeuristics(cleanedText)
    }

    private fun fromOutline(entries: List<OutlineEntry>, pages: List<PageText>): List<SectionData> {
        if (pages.isEmpty()) return emptyList()
        val lastIdx = pages.size - 1

        val sorted = entries
            .filter { it.pageIndex >= 0 && it.pageIndex <= lastIdx }
            .sortedBy { it.pageIndex }

        if (sorted.isEmpty()) {
            return fromHeuristics(pages.joinToString("\n\n") { it.text })
        }

        return sorted.mapIndexed { i, entry ->
            val start = entry.pageIndex
            val end = if (i + 1 < sorted.size) {
                maxOf(start, sorted[i + 1].pageIndex - 1)
            } else {
                lastIdx
            }
            val clampedEnd = minOf(end, lastIdx)
            val text = pages.slice(start..clampedEnd).joinToString("\n\n") { it.text }
            SectionData(
                title = entry.title,
                order = i,
                startPage = start + 1,
                endPage = clampedEnd + 1,
                rawText = text,
            )
        }
    }

    private fun fromHeuristics(cleanedText: String): List<SectionData> {
        val trimmedAll = cleanedText.trim()
        if (trimmedAll.isEmpty()) return emptyList()

        val paragraphs = cleanedText.split("\n\n")
        val result = mutableListOf<SectionData>()
        val buffer = mutableListOf<String>()
        var wordCount = 0
        var pendingTitle: String? = null
        var order = 0

        fun flush() {
            if (buffer.isEmpty()) return
            result.add(
                SectionData(
                    title = pendingTitle ?: "Section ${order + 1}",
                    order = order,
                    startPage = 1,
                    endPage = 1,
                    rawText = buffer.joinToString("\n\n"),
                ),
            )
            order += 1
            buffer.clear()
            wordCount = 0
            pendingTitle = null
        }

        for (para in paragraphs) {
            val trimmed = para.trim()
            if (trimmed.isEmpty()) continue

            if (isHeading(trimmed)) {
                if (wordCount >= WORDS_PER_CHUNK / 2) {
                    flush()
                }
                pendingTitle = trimmed
            } else {
                buffer.add(trimmed)
                wordCount += trimmed.split(Regex("\\s+")).filter { it.isNotEmpty() }.size
                if (wordCount >= WORDS_PER_CHUNK) {
                    flush()
                }
            }
        }
        flush()
        return result
    }

    /** Short, no trailing period/question, title-case or all-caps, ≤10 words (iOS parity). */
    fun isHeading(text: String): Boolean {
        val t = text.trim()
        if (t.length !in 2..80) return false
        if (t.endsWith(".") || t.endsWith("?")) return false
        val words = t.split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (words.size > 10) return false
        val allCaps = t == t.uppercase() && t.any { it.isLetter() }
        val titleCase = words.all { word ->
            word.firstOrNull()?.isUpperCase() == true
        }
        return allCaps || titleCase
    }
}
