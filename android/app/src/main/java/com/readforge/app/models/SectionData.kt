package com.readforge.app.models

data class SectionData(
    val title: String,
    val order: Int,
    val startPage: Int,
    val endPage: Int,
    val rawText: String,
)
