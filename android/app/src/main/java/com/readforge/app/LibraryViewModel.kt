package com.readforge.app

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import android.net.Uri
import com.readforge.app.models.DocumentRecord
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class LibraryViewModel(application: Application) : AndroidViewModel(application) {

    private val repo = getApplication<ReadForgeApplication>().libraryRepository

    private val _documents = MutableStateFlow<List<DocumentRecord>>(emptyList())
    val documents: StateFlow<List<DocumentRecord>> = _documents.asStateFlow()

    private val _snackbarMessage = MutableStateFlow<String?>(null)
    val snackbarMessage: StateFlow<String?> = _snackbarMessage.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        _documents.value = repo.loadDocuments()
    }

    fun importPdf(uri: Uri) {
        viewModelScope.launch {
            repo.importPdf(uri)
                .onSuccess {
                    refresh()
                }
                .onFailure { t ->
                    _snackbarMessage.value = humanizeImportError(t)
                }
        }
    }

    fun consumeSnackbarMessage() {
        _snackbarMessage.value = null
    }

    private fun humanizeImportError(t: Throwable): String {
        val app = getApplication<Application>()
        return when (t.message) {
            "import_wrong_type" -> app.getString(R.string.import_wrong_type)
            "import_read_failed" -> app.getString(R.string.import_read_failed)
            else -> t.message?.takeIf { it.isNotBlank() }
                ?: app.getString(R.string.import_unknown_error)
        }
    }
}
