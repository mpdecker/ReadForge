package com.readforge.app.models

/** PDF outline bookmark: zero-based page index (matches iOS / PDFKit). */
data class OutlineEntry(
    val title: String,
    val pageIndex: Int,
)
