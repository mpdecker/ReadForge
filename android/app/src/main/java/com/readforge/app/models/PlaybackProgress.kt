package com.readforge.app.models

data class PlaybackProgress(
    val documentId: String,
    val utteranceIndex: Int,
    val characterOffset: Int = 0,
    val updatedAtEpochMs: Long = System.currentTimeMillis(),
)
