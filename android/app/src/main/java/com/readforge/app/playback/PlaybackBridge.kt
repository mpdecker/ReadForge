package com.readforge.app.playback

/**
 * Bridge from [PlaybackMediaService] / system media keys to [ReadAloudPlaybackEngine].
 * The engine registers handlers in its initializer; do not clear from the player activity.
 */
object PlaybackBridge {
    var togglePlayPause: (() -> Unit)? = null
    var stopPlayback: (() -> Unit)? = null
    var skipNext: (() -> Unit)? = null
    var skipPrevious: (() -> Unit)? = null

    fun clear() {
        togglePlayPause = null
        stopPlayback = null
        skipNext = null
        skipPrevious = null
    }
}
