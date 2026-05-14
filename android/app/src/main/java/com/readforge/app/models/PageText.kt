package com.readforge.app.models

data class PageText(
    val pageNumber: Int,
    val text: String,
)

data class PdfExtractionSummary(
    val pages: List<PageText>,
) {
    val pageCount: Int get() = pages.size

    val totalCharacterCount: Int get() = pages.sumOf { it.text.length }

    /** Same heuristic as iOS `PDFExtractionService.isLikelyScanned` (under 50 chars/page average). */
    val isLikelyScanned: Boolean
        get() {
            if (pages.isEmpty()) return false
            return totalCharacterCount / pages.size < 50
        }
}
