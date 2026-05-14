package com.readforge.app

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.CreationExtras
import com.readforge.app.models.DocumentRecord
import com.readforge.app.models.OutlineEntry
import com.readforge.app.models.ProcessedDocument
import com.readforge.app.pdf.PdfTextExtractionService
import com.readforge.app.pdf.SectionDetectionService
import com.readforge.app.pdf.TextCleanupService
import com.readforge.app.speech.SentenceChunker
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class PlaybackUi(
    val chunks: List<String> = emptyList(),
    val index: Int = 0,
    val isPlaying: Boolean = false,
) {
    val canPlay: Boolean get() = chunks.isNotEmpty()
}

class PlayerViewModel(
    application: Application,
    private val documentId: String?,
) : AndroidViewModel(application) {

    private val repo = getApplication<ReadForgeApplication>().libraryRepository
    private val progressStore = getApplication<ReadForgeApplication>().playbackProgressStore
    private val playbackEngine = getApplication<ReadForgeApplication>().readAloudPlaybackEngine

    private val _state = MutableStateFlow<PlayerUiState>(PlayerUiState.Loading)
    val state: StateFlow<PlayerUiState> = _state.asStateFlow()

    val playback: StateFlow<PlaybackUi> = playbackEngine.playback

    init {
        if (documentId.isNullOrBlank()) {
            _state.value = PlayerUiState.MissingDocument
        } else {
            playbackEngine.prepareLoad(documentId)
            viewModelScope.launch {
                _state.value = PlayerUiState.Loading
                val document = repo.getDocument(documentId)
                if (document == null) {
                    playbackEngine.abandonSessionForDocument(documentId)
                    _state.value = PlayerUiState.MissingDocument
                    return@launch
                }
                val file = repo.internalPdfFile(document)
                PdfTextExtractionService.extract(file)
                    .onSuccess { summary ->
                        val processed = withContext(Dispatchers.Default) {
                            val cleaned = TextCleanupService.clean(summary.pages)
                            val outlineEntries = emptyList<OutlineEntry>()
                            val sections = SectionDetectionService.detect(
                                pages = summary.pages,
                                outlineEntries = outlineEntries,
                                cleanedText = cleaned,
                            )
                            ProcessedDocument(
                                extraction = summary,
                                cleanedText = cleaned,
                                sections = sections,
                            )
                        }
                        val chunks = SentenceChunker.chunk(processed.cleanedText).filter { it.isNotEmpty() }
                        val restoredIndex = withContext(Dispatchers.IO) {
                            val saved = progressStore.load(documentId)
                            if (chunks.isEmpty() || saved == null) {
                                0
                            } else {
                                saved.utteranceIndex.coerceIn(0, chunks.lastIndex)
                            }
                        }
                        playbackEngine.bindPlayback(
                            documentId = document.id,
                            displayTitle = document.displayTitle,
                            chunks = chunks,
                            restoredIndex = restoredIndex,
                        )
                        _state.value = PlayerUiState.Ready(document, processed)
                    }
                    .onFailure { t ->
                        playbackEngine.onLoadFailed(documentId)
                        _state.value = PlayerUiState.Error(humanizeExtractionError(t))
                    }
            }
        }
    }

    fun togglePlayPause() = playbackEngine.togglePlayPause()

    fun stopPlayback() = playbackEngine.stopPlayback()

    fun skipToNextChunk() = playbackEngine.skipToNextChunk()

    fun skipToPreviousChunk() = playbackEngine.skipToPreviousChunk()

    private fun humanizeExtractionError(t: Throwable): String {
        val appCtx = getApplication<Application>()
        return when (t.message) {
            "cannot_open" -> appCtx.getString(R.string.extract_cannot_open)
            "password_protected" -> appCtx.getString(R.string.extract_password_protected)
            "no_pages" -> appCtx.getString(R.string.extract_no_pages)
            else -> t.message?.takeIf { it.isNotBlank() }
                ?: appCtx.getString(R.string.extract_unknown_error)
        }
    }

    override fun onCleared() {
        playbackEngine.persistIfActiveDocument(documentId)
        super.onCleared()
    }

    companion object {
        fun factory(documentId: String?) = object : ViewModelProvider.Factory {
            override fun <T : ViewModel> create(modelClass: Class<T>, extras: CreationExtras): T {
                val application = checkNotNull(
                    extras[ViewModelProvider.AndroidViewModelFactory.APPLICATION_KEY],
                ) as Application
                if (modelClass.isAssignableFrom(PlayerViewModel::class.java)) {
                    @Suppress("UNCHECKED_CAST")
                    return PlayerViewModel(application, documentId) as T
                }
                throw IllegalArgumentException("Unknown ViewModel class: ${modelClass.name}")
            }
        }
    }
}

sealed interface PlayerUiState {
    data object Loading : PlayerUiState
    data object MissingDocument : PlayerUiState
    data class Ready(val document: DocumentRecord, val processed: ProcessedDocument) : PlayerUiState
    data class Error(val message: String) : PlayerUiState
}
