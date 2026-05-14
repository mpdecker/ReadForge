package com.readforge.app.models

data class DocumentRecord(
    val id: String,
    val displayTitle: String,
    /** File name only, under app filesDir/pdfs/ */
    val storedFileName: String,
    val importedAtEpochMs: Long,
)
