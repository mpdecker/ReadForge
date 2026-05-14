package com.readforge.app.storage

import com.readforge.app.models.DocumentRecord
import java.io.File
import org.json.JSONArray
import org.json.JSONObject

class LibraryIndexStore(rootDir: File) {

    private val indexFile = File(rootDir, INDEX_FILE_NAME)
    val pdfsDirectory: File = File(rootDir, PDF_SUBDIR).apply { mkdirs() }

    @Synchronized
    fun loadAll(): List<DocumentRecord> {
        if (!indexFile.exists()) return emptyList()
        return runCatching {
            val text = indexFile.readText()
            val array = JSONArray(text)
            buildList {
                for (i in 0 until array.length()) {
                    fromJson(array.getJSONObject(i))?.let { add(it) }
                }
            }.sortedByDescending { it.importedAtEpochMs }
        }.getOrDefault(emptyList())
    }

    @Synchronized
    fun append(record: DocumentRecord) {
        val existing = loadAll().toMutableList()
        existing.removeAll { it.id == record.id }
        existing.add(record)
        writeAll(existing)
    }

    @Synchronized
    fun findById(id: String): DocumentRecord? = loadAll().find { it.id == id }

    private fun writeAll(documents: List<DocumentRecord>) {
        val array = JSONArray()
        documents.forEach { array.put(it.toJson()) }
        indexFile.writeText(array.toString())
    }

    private fun DocumentRecord.toJson(): JSONObject =
        JSONObject().apply {
            put("id", id)
            put("displayTitle", displayTitle)
            put("storedFileName", storedFileName)
            put("importedAtEpochMs", importedAtEpochMs)
        }

    private fun fromJson(o: JSONObject): DocumentRecord? =
        runCatching {
            DocumentRecord(
                id = o.getString("id"),
                displayTitle = o.getString("displayTitle"),
                storedFileName = o.getString("storedFileName"),
                importedAtEpochMs = o.getLong("importedAtEpochMs"),
            )
        }.getOrNull()

    companion object {
        private const val INDEX_FILE_NAME = "library_documents.json"
        private const val PDF_SUBDIR = "pdfs"
    }
}
