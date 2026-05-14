package com.readforge.app.playback

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.Manifest
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.media.app.NotificationCompat.MediaStyle
import com.readforge.app.PlayerActivity
import com.readforge.app.R

/**
 * Foreground playback controls: MediaStyle notification + [MediaSessionCompat] for
 * lock screen / headset / BT (transport parity with iOS Now Playing basics).
 */
class PlaybackMediaService : Service() {

    private lateinit var mediaSession: MediaSessionCompat

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
        mediaSession = MediaSessionCompat(this, TAG).apply {
            setFlags(
                MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS,
            )
            setCallback(
                object : MediaSessionCompat.Callback() {
                    override fun onPlay() {
                        PlaybackBridge.togglePlayPause?.invoke()
                    }

                    override fun onPause() {
                        PlaybackBridge.togglePlayPause?.invoke()
                    }

                    override fun onSkipToNext() {
                        PlaybackBridge.skipNext?.invoke()
                    }

                    override fun onSkipToPrevious() {
                        PlaybackBridge.skipPrevious?.invoke()
                    }

                    override fun onStop() {
                        PlaybackBridge.stopPlayback?.invoke()
                    }
                },
            )
            isActive = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.getStringExtra(EXTRA_CMD)) {
            CMD_TOGGLE -> PlaybackBridge.togglePlayPause?.invoke()
            CMD_STOP -> PlaybackBridge.stopPlayback?.invoke()
            CMD_NEXT -> PlaybackBridge.skipNext?.invoke()
            CMD_PREV -> PlaybackBridge.skipPrevious?.invoke()
        }
        if (intent?.action == ACTION_SYNC) {
            val title = intent.getStringExtra(EXTRA_TITLE) ?: getString(R.string.player_title)
            val documentId = intent.getStringExtra(EXTRA_DOCUMENT_ID)
            val isPlaying = intent.getBooleanExtra(EXTRA_PLAYING, false)
            val index = intent.getIntExtra(EXTRA_INDEX, 0)
            val total = intent.getIntExtra(EXTRA_TOTAL, 0)
            val canPlay = intent.getBooleanExtra(EXTRA_CAN_PLAY, false)
            applySessionAndNotification(title, documentId, isPlaying, index, total, canPlay)
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        if (::mediaSession.isInitialized) {
            mediaSession.isActive = false
            mediaSession.release()
        }
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun applySessionAndNotification(
        title: String,
        documentId: String?,
        isPlaying: Boolean,
        index: Int,
        total: Int,
        canPlay: Boolean,
    ) {
        val durationMs = (total.coerceAtLeast(1) * EST_MS_PER_UTTERANCE).toLong()
        val positionMs = (index.coerceAtLeast(0) * EST_MS_PER_UTTERANCE).toLong()

        mediaSession.setMetadata(
            MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
                .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_TITLE, title)
                .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)
                .build(),
        )

        val state = if (!canPlay) {
            PlaybackStateCompat.STATE_NONE
        } else if (isPlaying) {
            PlaybackStateCompat.STATE_PLAYING
        } else {
            PlaybackStateCompat.STATE_PAUSED
        }

        val actions = PlaybackStateCompat.ACTION_PLAY_PAUSE or
            PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
            PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
            PlaybackStateCompat.ACTION_STOP

        mediaSession.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(actions)
                .setState(state, positionMs, if (isPlaying) 1f else 0f)
                .build(),
        )

        val notification = buildNotification(title, documentId, isPlaying, index, total, canPlay)
        if (canPlay && isPlaying) {
            if (canPostNotifications()) {
                startForeground(NOTIFICATION_ID, notification)
            }
        } else {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_DETACH)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(false)
            }
            if (canPlay) {
                notifyIfAllowed(NOTIFICATION_ID, notification)
            } else {
                NotificationManagerCompat.from(this).cancel(NOTIFICATION_ID)
            }
        }
    }

    private fun canPostNotifications(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun notifyIfAllowed(id: Int, notification: Notification) {
        if (!canPostNotifications()) return
        try {
            NotificationManagerCompat.from(this).notify(id, notification)
        } catch (_: SecurityException) {
            // Revoked at runtime after check
        }
    }

    private fun buildNotification(
        title: String,
        documentId: String?,
        isPlaying: Boolean,
        index: Int,
        total: Int,
        canPlay: Boolean,
    ): Notification {
        val openPlayer = PendingIntent.getActivity(
            this,
            0,
            Intent(this, PlayerActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                documentId?.let { putExtra(PlayerActivity.EXTRA_DOCUMENT_ID, it) }
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val toggle = servicePending(CMD_TOGGLE, 1)
        val stop = servicePending(CMD_STOP, 2)
        val next = servicePending(CMD_NEXT, 3)
        val prev = servicePending(CMD_PREV, 4)

        val playPauseIcon = if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        val playPauseTitle = if (isPlaying) {
            getString(R.string.pause)
        } else {
            getString(R.string.play)
        }

        val style = MediaStyle()
            .setMediaSession(mediaSession.sessionToken)
            .setShowActionsInCompactView(0, 1, 2)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(
                if (total > 0) {
                    getString(R.string.notification_position, index + 1, total)
                } else {
                    getString(R.string.player_title)
                },
            )
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentIntent(openPlayer)
            .setOnlyAlertOnce(true)
            .setOngoing(isPlaying && canPlay)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setStyle(style)
            .addAction(android.R.drawable.ic_media_previous, getString(R.string.skip_previous), prev)
            .addAction(playPauseIcon, playPauseTitle, toggle)
            .addAction(android.R.drawable.ic_media_next, getString(R.string.skip_next), next)
            .addAction(android.R.drawable.ic_delete, getString(R.string.stop), stop)
            .build()
    }

    private fun servicePending(cmd: String, requestCode: Int): PendingIntent =
        PendingIntent.getService(
            this,
            requestCode,
            Intent(this, PlaybackMediaService::class.java).putExtra(EXTRA_CMD, cmd),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                getString(R.string.notification_channel_playback_name),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = getString(R.string.notification_channel_playback_description)
                setShowBadge(false)
            },
        )
    }

    companion object {
        private const val TAG = "ReadForgePlayback"
        private const val CHANNEL_ID = "readforge_playback"
        private const val NOTIFICATION_ID = 7101
        private const val EST_MS_PER_UTTERANCE = 25_000L

        const val ACTION_SYNC = "com.readforge.app.playback.SYNC"
        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_DOCUMENT_ID = "extra_document_id"
        const val EXTRA_PLAYING = "extra_playing"
        const val EXTRA_INDEX = "extra_index"
        const val EXTRA_TOTAL = "extra_total"
        const val EXTRA_CAN_PLAY = "extra_can_play"
        private const val EXTRA_CMD = "extra_cmd"
        private const val CMD_TOGGLE = "toggle"
        private const val CMD_STOP = "stop"
        private const val CMD_NEXT = "next"
        private const val CMD_PREV = "prev"

        fun sync(
            context: Context,
            title: String,
            documentId: String?,
            isPlaying: Boolean,
            index: Int,
            total: Int,
            canPlay: Boolean,
        ) {
            val i = Intent(context, PlaybackMediaService::class.java).apply {
                action = ACTION_SYNC
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_DOCUMENT_ID, documentId)
                putExtra(EXTRA_PLAYING, isPlaying)
                putExtra(EXTRA_INDEX, index)
                putExtra(EXTRA_TOTAL, total)
                putExtra(EXTRA_CAN_PLAY, canPlay)
            }
            ContextCompat.startForegroundService(context, i)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, PlaybackMediaService::class.java))
        }
    }
}
