package com.readforge.app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.readforge.app.models.ProcessedDocument
import com.readforge.app.ui.theme.ReadForgeTheme

class PlayerActivity : ComponentActivity() {

    private val requestNotificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    private val viewModel: PlayerViewModel by viewModels {
        PlayerViewModel.factory(intent.getStringExtra(EXTRA_DOCUMENT_ID))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            ReadForgeTheme {
                val state by viewModel.state.collectAsStateWithLifecycle()
                val playback by viewModel.playback.collectAsStateWithLifecycle()
                PlayerScreen(
                    state = state,
                    playback = playback,
                    onNavigateUp = { finish() },
                    onTogglePlayPause = { viewModel.togglePlayPause() },
                    onStopPlayback = { viewModel.stopPlayback() },
                    onSkipPrevious = { viewModel.skipToPreviousChunk() },
                    onSkipNext = { viewModel.skipToNextChunk() },
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    override fun onStart() {
        super.onStart()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                requestNotificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
    }

    companion object {
        const val EXTRA_DOCUMENT_ID = "extra_document_id"

        fun createIntent(context: Context, documentId: String): Intent =
            Intent(context, PlayerActivity::class.java).putExtra(EXTRA_DOCUMENT_ID, documentId)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PlayerScreen(
    state: PlayerUiState,
    playback: PlaybackUi,
    onNavigateUp: () -> Unit,
    onTogglePlayPause: () -> Unit,
    onStopPlayback: () -> Unit,
    onSkipPrevious: () -> Unit,
    onSkipNext: () -> Unit,
) {
    val title = when (state) {
        is PlayerUiState.Ready -> state.document.displayTitle
        else -> stringResource(R.string.player_title)
    }

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(title) },
                navigationIcon = {
                    IconButton(onClick = onNavigateUp) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.navigate_up),
                        )
                    }
                },
            )
        },
    ) { innerPadding ->
        when (state) {
            PlayerUiState.Loading -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }

            PlayerUiState.MissingDocument -> {
                Text(
                    text = stringResource(R.string.document_missing),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onBackground,
                    modifier = Modifier.padding(innerPadding).padding(24.dp),
                )
            }

            is PlayerUiState.Error -> {
                Text(
                    text = state.message,
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(innerPadding).padding(24.dp),
                )
            }

            is PlayerUiState.Ready -> {
                PlayerReadyBody(
                    processed = state.processed,
                    playback = playback,
                    onTogglePlayPause = onTogglePlayPause,
                    onStopPlayback = onStopPlayback,
                    onSkipPrevious = onSkipPrevious,
                    onSkipNext = onSkipNext,
                    modifier = Modifier.padding(innerPadding).padding(horizontal = 24.dp),
                )
            }
        }
    }
}

@Composable
private fun PlayerReadyBody(
    processed: ProcessedDocument,
    playback: PlaybackUi,
    onTogglePlayPause: () -> Unit,
    onStopPlayback: () -> Unit,
    onSkipPrevious: () -> Unit,
    onSkipNext: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val summary = processed.extraction
    val previewChars = 12_000
    val cleaned = processed.cleanedText
    val preview = if (cleaned.length <= previewChars) {
        cleaned
    } else {
        cleaned.take(previewChars) + "\n…"
    }

    val sectionLines = processed.sections.take(24).joinToString("\n") { section ->
        "${section.order + 1}. ${section.title}"
    }

    val lastChunkIndex = playback.chunks.lastIndex

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState()),
    ) {
        Text(
            text = stringResource(
                R.string.pipeline_summary,
                summary.pageCount,
                summary.totalCharacterCount,
                processed.cleanedCharacterCount,
                processed.sections.size,
            ),
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onBackground,
        )
        Spacer(modifier = Modifier.height(12.dp))
        if (summary.isLikelyScanned) {
            Text(
                text = stringResource(R.string.needs_ocr_message),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.error,
            )
            Spacer(modifier = Modifier.height(12.dp))
        }

        Text(
            text = stringResource(R.string.playback_heading),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.primary,
        )
        Spacer(modifier = Modifier.height(6.dp))
        if (!playback.canPlay) {
            Text(
                text = stringResource(R.string.playback_no_chunks),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onBackground,
            )
        } else {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(
                    onClick = onSkipPrevious,
                    enabled = playback.index > 0,
                ) {
                    Icon(Icons.Filled.SkipPrevious, contentDescription = stringResource(R.string.skip_previous))
                }
                IconButton(onClick = onTogglePlayPause) {
                    Icon(
                        imageVector = if (playback.isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                        contentDescription = if (playback.isPlaying) {
                            stringResource(R.string.pause)
                        } else {
                            stringResource(R.string.play)
                        },
                    )
                }
                IconButton(onClick = onStopPlayback) {
                    Icon(Icons.Filled.Stop, contentDescription = stringResource(R.string.stop))
                }
                IconButton(
                    onClick = onSkipNext,
                    enabled = playback.index < lastChunkIndex,
                ) {
                    Icon(Icons.Filled.SkipNext, contentDescription = stringResource(R.string.skip_next))
                }
            }
            Text(
                text = stringResource(
                    R.string.playback_position,
                    playback.index + 1,
                    playback.chunks.size,
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onBackground,
                modifier = Modifier.padding(top = 4.dp),
            )
            Text(
                text = stringResource(R.string.playback_pause_hint),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 6.dp),
            )
            Text(
                text = stringResource(R.string.playback_background_hint),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 6.dp),
            )
        }
        Spacer(modifier = Modifier.height(16.dp))

        if (sectionLines.isNotEmpty()) {
            Text(
                text = stringResource(R.string.sections_heading),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
            )
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                text = sectionLines,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onBackground,
            )
            Spacer(modifier = Modifier.height(12.dp))
        }
        Text(
            text = stringResource(R.string.extract_preview_cleaned_heading),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.primary,
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = preview.ifBlank { stringResource(R.string.extract_empty_text) },
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onBackground,
        )
    }
}
