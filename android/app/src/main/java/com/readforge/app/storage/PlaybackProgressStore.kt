package com.readforge.app.storage

import com.readforge.app.models.PlaybackProgress
import java.io.File
import org.json.JSONObject

/**
 * Persists per-document playback cursor (utterance index + optional character offset).
 * File layout mirrors the library JSON index: one JSON object in app filesDir.
 */
class PlaybackProgressStore(private val rootDir: File) {

    private val file = File(rootDir, FILE_NAME)

    @Synchronized
    fun load(documentId: String): PlaybackProgress? {
        if (!file.exists()) return null
        return runCatching {
            val root = JSONObject(file.readText())
            if (!root.has(documentId)) return@runCatching null
            val o = root.getJSONObject(documentId)
            PlaybackProgress(
                documentId = documentId,
                utteranceIndex = o.getInt("utteranceIndex"),
                characterOffset = o.optInt("characterOffset", 0),
                updatedAtEpochMs = o.optLong("updatedAtEpochMs", System.currentTimeMillis()),
            )
        }.getOrNull()
    }

    @Synchronized
    fun save(progress: PlaybackProgress) {
        val root = if (file.exists()) {
            runCatching { JSONObject(file.readText()) }.getOrDefault(JSONObject())
        } else {
            JSONObject()
        }
        root.put(
            progress.documentId,
            JSONObject().apply {
                put("utteranceIndex", progress.utteranceIndex)
                put("characterOffset", progress.characterOffset)
                put("updatedAtEpochMs", progress.updatedAtEpochMs)
            },
        )
        file.writeText(root.toString())
    }

    @Synchronized
    fun clear(documentId: String) {
        if (!file.exists()) return
        runCatching {
            val root = JSONObject(file.readText())
            root.remove(documentId)
            if (root.length() == 0) {
                file.delete()
            } else {
                file.writeText(root.toString())
            }
        }
    }

    companion object {
        private const val FILE_NAME = "playback_progress.json"
    }
}
