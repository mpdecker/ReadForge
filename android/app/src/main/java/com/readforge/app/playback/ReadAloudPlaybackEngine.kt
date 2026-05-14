package com.readforge.app.playback

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import com.readforge.app.PlaybackUi
import com.readforge.app.ReadForgeApplication
import com.readforge.app.models.PlaybackProgress
import com.readforge.app.R
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * Process-scoped TTS playback so leaving [com.readforge.app.PlayerActivity] does not stop reading.
 * [PlaybackMediaService] is driven from here; [PlaybackBridge] targets this engine for transport keys.
 */
class ReadAloudPlaybackEngine(
    private val app: ReadForgeApplication,
) {

    private val progressStore = app.playbackProgressStore
    private val audioManager = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private val scope = app.applicationScope

    private val _playback = MutableStateFlow(PlaybackUi())
    val playback: StateFlow<PlaybackUi> = _playback.asStateFlow()

    private var activeDocumentId: String? = null
    private var sessionDisplayTitle: String = ""

    private var tts: TextToSpeech? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var suppressUtteranceAdvance = false

    private val audioFocusListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        if (focusChange == AudioManager.AUDIOFOCUS_LOSS ||
            focusChange == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT ||
            focusChange == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK
        ) {
            mainHandler.post { pausePlaybackInternal(fromAudioFocus = true) }
        }
    }

    init {
        PlaybackBridge.togglePlayPause = { togglePlayPause() }
        PlaybackBridge.stopPlayback = { stopPlayback() }
        PlaybackBridge.skipNext = { skipToNextChunk() }
        PlaybackBridge.skipPrevious = { skipToPreviousChunk() }
    }

    /**
     * Call when opening the player for [targetDocumentId]. If another document was active, that session is stopped.
     */
    fun prepareLoad(targetDocumentId: String) {
        if (activeDocumentId != null && activeDocumentId != targetDocumentId) {
            stopPlaybackAndClearActiveSession()
        }
    }

    fun bindPlayback(
        documentId: String,
        displayTitle: String,
        chunks: List<String>,
        restoredIndex: Int,
    ) {
        sessionDisplayTitle = displayTitle
        val safeIndex = if (chunks.isEmpty()) 0 else restoredIndex.coerceIn(0, chunks.lastIndex)
        val existing = _playback.value
        val sameSession = documentId == activeDocumentId &&
            existing.chunks.isNotEmpty() &&
            chunks.isNotEmpty() &&
            existing.chunks.size == chunks.size &&
            existing.chunks.first() == chunks.first() &&
            existing.chunks.last() == chunks.last()
        if (sameSession) {
            activeDocumentId = documentId
            _playback.update { it.copy(chunks = chunks) }
            syncNotification()
            return
        }
        suppressUtteranceAdvance = true
        tts?.stop()
        suppressUtteranceAdvance = false
        activeDocumentId = documentId
        _playback.value = PlaybackUi(chunks = chunks, index = safeIndex, isPlaying = false)
        syncNotification()
    }

    fun abandonSessionForDocument(documentId: String) {
        if (activeDocumentId == documentId) {
            stopPlaybackAndClearActiveSession()
        }
    }

    fun onLoadFailed(documentId: String) {
        if (activeDocumentId == documentId) {
            stopPlaybackAndClearActiveSession()
        }
    }

    fun persistIfActiveDocument(documentId: String?) {
        val id = documentId ?: return
        if (activeDocumentId != id) return
        scope.launch(Dispatchers.IO) {
            persistProgressBlocking(id)
        }
    }

    fun togglePlayPause() {
        val ui = _playback.value
        if (!ui.canPlay) return
        if (ui.isPlaying) {
            pausePlaybackInternal(fromAudioFocus = false)
        } else {
            startPlayback()
        }
    }

    fun stopPlayback() {
        suppressUtteranceAdvance = true
        tts?.stop()
        mainHandler.post {
            suppressUtteranceAdvance = false
            _playback.update { it.copy(isPlaying = false, index = 0) }
            persistProgress()
            abandonAudioFocus()
            syncNotification()
        }
    }

    fun skipToNextChunk() {
        val ui = _playback.value
        if (ui.chunks.isEmpty()) return
        val wasPlaying = ui.isPlaying
        suppressUtteranceAdvance = true
        tts?.stop()
        mainHandler.post {
            suppressUtteranceAdvance = false
            val last = ui.chunks.lastIndex
            val idx = minOf(ui.index + 1, last)
            _playback.update { it.copy(index = idx) }
            persistProgress()
            if (wasPlaying) {
                _playback.update { it.copy(isPlaying = true) }
                speakCurrentChunk()
            }
            syncNotification()
        }
    }

    fun skipToPreviousChunk() {
        val ui = _playback.value
        if (ui.chunks.isEmpty()) return
        val wasPlaying = ui.isPlaying
        suppressUtteranceAdvance = true
        tts?.stop()
        mainHandler.post {
            suppressUtteranceAdvance = false
            val idx = maxOf(ui.index - 1, 0)
            _playback.update { it.copy(index = idx) }
            persistProgress()
            if (wasPlaying) {
                _playback.update { it.copy(isPlaying = true) }
                speakCurrentChunk()
            }
            syncNotification()
        }
    }

    private fun startPlayback() {
        if (!_playback.value.canPlay) return
        ensureTts { success ->
            if (!success) return@ensureTts
            requestAudioFocus()
            _playback.update { it.copy(isPlaying = true) }
            syncNotification()
            speakCurrentChunk()
        }
    }

    private fun pausePlaybackInternal(fromAudioFocus: Boolean) {
        suppressUtteranceAdvance = true
        tts?.stop()
        mainHandler.post {
            suppressUtteranceAdvance = false
            _playback.update { it.copy(isPlaying = false) }
            persistProgress()
            if (fromAudioFocus) {
                abandonAudioFocus()
            }
            syncNotification()
        }
    }

    private fun speakCurrentChunk() {
        val ui = _playback.value
        if (!ui.isPlaying || ui.index !in ui.chunks.indices) return
        val id = "rf-${ui.index}"
        val params = android.os.Bundle().apply {
            putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, id)
        }
        tts?.speak(ui.chunks[ui.index], TextToSpeech.QUEUE_FLUSH, params, id)
    }

    private fun onUtteranceFinished() {
        if (suppressUtteranceAdvance) return
        val ui = _playback.value
        if (!ui.isPlaying) return
        val next = ui.index + 1
        if (next >= ui.chunks.size) {
            _playback.update { it.copy(isPlaying = false, index = ui.chunks.lastIndex.coerceAtLeast(0)) }
            persistProgress()
            abandonAudioFocus()
            syncNotification()
            return
        }
        _playback.update { it.copy(index = next) }
        persistProgress()
        syncNotification()
        speakCurrentChunk()
    }

    private fun onUtteranceErrored() {
        if (suppressUtteranceAdvance) return
        _playback.update { it.copy(isPlaying = false) }
        persistProgress()
        abandonAudioFocus()
        syncNotification()
    }

    private fun persistProgress() {
        val id = activeDocumentId ?: return
        scope.launch(Dispatchers.IO) {
            persistProgressBlocking(id)
        }
    }

    private fun persistProgressBlocking(documentId: String) {
        val snap = _playback.value
        if (snap.chunks.isEmpty()) {
            progressStore.clear(documentId)
            return
        }
        val clamped = snap.index.coerceIn(0, snap.chunks.lastIndex)
        progressStore.save(
            PlaybackProgress(
                documentId = documentId,
                utteranceIndex = clamped,
                characterOffset = 0,
                updatedAtEpochMs = System.currentTimeMillis(),
            ),
        )
    }

    private fun stopPlaybackAndClearActiveSession() {
        suppressUtteranceAdvance = true
        tts?.stop()
        suppressUtteranceAdvance = false
        activeDocumentId?.let { id ->
            scope.launch(Dispatchers.IO) {
                persistProgressBlocking(id)
            }
        }
        activeDocumentId = null
        sessionDisplayTitle = ""
        _playback.value = PlaybackUi()
        abandonAudioFocus()
        PlaybackMediaService.stop(app)
    }

    private fun syncNotification() {
        val p = _playback.value
        val id = activeDocumentId
        if (!p.canPlay || id == null) {
            PlaybackMediaService.stop(app)
            return
        }
        PlaybackMediaService.sync(
            app,
            sessionDisplayTitle.ifBlank { app.getString(R.string.player_title) },
            id,
            p.isPlaying,
            p.index,
            p.chunks.size,
            p.canPlay,
        )
    }

    private fun ensureTts(onReady: (Boolean) -> Unit) {
        if (tts != null) {
            onReady(true)
            return
        }
        tts = TextToSpeech(app) { status ->
            if (status != TextToSpeech.SUCCESS) {
                mainHandler.post { onReady(false) }
                return@TextToSpeech
            }
            val engine = tts ?: return@TextToSpeech
            engine.language = Locale.US
            engine.setSpeechRate(1.0f)
            engine.setPitch(1.0f)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                engine.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                )
            }
            engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}

                override fun onDone(utteranceId: String?) {
                    mainHandler.post { onUtteranceFinished() }
                }

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    mainHandler.post { onUtteranceErrored() }
                }

                override fun onError(utteranceId: String?, errorCode: Int) {
                    mainHandler.post { onUtteranceErrored() }
                }
            })
            mainHandler.post { onReady(true) }
        }
    }

    private fun requestAudioFocus(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                )
                .setOnAudioFocusChangeListener(audioFocusListener)
                .build()
            audioFocusRequest = req
            audioManager.requestAudioFocus(req) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                audioFocusListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
            ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
    }

    private fun abandonAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(audioFocusListener)
        }
        audioFocusRequest = null
    }
}
