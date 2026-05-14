package com.readforge.app.storage

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import com.readforge.app.models.DocumentRecord
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class LibraryRepository(context: Context) {

    private val appContext = context.applicationContext
    private val indexStore = LibraryIndexStore(appContext.filesDir)

    fun loadDocuments(): List<DocumentRecord> = indexStore.loadAll()

    fun getDocument(id: String): DocumentRecord? = indexStore.findById(id)

    fun internalPdfFile(record: DocumentRecord): File =
        File(indexStore.pdfsDirectory, record.storedFileName)

    suspend fun importPdf(uri: Uri): Result<DocumentRecord> = withContext(Dispatchers.IO) {
        runCatching {
            val resolver = appContext.contentResolver
            val type = resolver.getType(uri)
            val displayName = queryDisplayName(uri) ?: "document.pdf"
            require(isPdf(displayName, type)) { "import_wrong_type" }

            val id = UUID.randomUUID().toString()
            val storedName = "$id.pdf"
            val dest = File(indexStore.pdfsDirectory, storedName)

            resolver.openInputStream(uri)?.use { input ->
                FileOutputStream(dest).use { output -> input.copyTo(output) }
            } ?: error("import_read_failed")

            val record = DocumentRecord(
                id = id,
                displayTitle = displayName.trim().ifBlank { "document.pdf" },
                storedFileName = storedName,
                importedAtEpochMs = System.currentTimeMillis(),
            )
            indexStore.append(record)
            record
        }
    }

    private fun isPdf(displayName: String, mimeType: String?): Boolean {
        if (mimeType == "application/pdf") return true
        return displayName.lowercase().endsWith(".pdf")
    }

    private fun queryDisplayName(uri: Uri): String? {
        val projection = arrayOf(OpenableColumns.DISPLAY_NAME)
        return appContext.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return@use null
            val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (idx < 0) null else cursor.getString(idx)
        }
    }
}
