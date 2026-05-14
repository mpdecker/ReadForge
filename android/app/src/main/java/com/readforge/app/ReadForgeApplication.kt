package com.readforge.app

import android.app.Application
import com.readforge.app.playback.ReadAloudPlaybackEngine
import com.readforge.app.storage.LibraryRepository
import com.readforge.app.storage.PlaybackProgressStore
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

class ReadForgeApplication : Application() {

    val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    lateinit var libraryRepository: LibraryRepository
        private set

    lateinit var playbackProgressStore: PlaybackProgressStore
        private set

    lateinit var readAloudPlaybackEngine: ReadAloudPlaybackEngine
        private set

    override fun onCreate() {
        super.onCreate()
        PDFBoxResourceLoader.init(applicationContext)
        libraryRepository = LibraryRepository(this)
        playbackProgressStore = PlaybackProgressStore(filesDir)
        readAloudPlaybackEngine = ReadAloudPlaybackEngine(this)
    }
}
