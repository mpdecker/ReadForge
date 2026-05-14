package com.readforge.app.models

/** Raw PDF extraction plus deterministic cleanup and section chunks. */
data class ProcessedDocument(
    val extraction: PdfExtractionSummary,
    val cleanedText: String,
    val sections: List<SectionData>,
) {
    val cleanedCharacterCount: Int get() = cleanedText.length
}
