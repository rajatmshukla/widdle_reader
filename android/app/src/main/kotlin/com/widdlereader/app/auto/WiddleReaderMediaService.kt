package com.widdlereader.app.auto

import android.app.PendingIntent
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.MediaDescriptionCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Base64
import android.util.Log
import androidx.media.MediaBrowserServiceCompat
import com.widdlereader.app.MainActivity
import com.widdlereader.app.R
import kotlinx.coroutines.*

/**
 * Optimized MediaBrowserService for Android Auto
 * 
 * Uses AudioSessionBridge for:
 * - Direct MediaSession control (zero latency)
 * - Fallback to SharedPreferences if needed
 * - Proper integration with existing audio architecture
 */
class WiddleReaderMediaService : MediaBrowserServiceCompat() {
    
    companion object {
        private const val TAG = "WiddleMediaService"
        private const val ROOT_ID = "widdle_reader_root"
        private const val MAX_RECENT_ITEMS = 15
        private const val MAX_BROWSE_ITEMS = 25
    }
    
    private var mediaSession: MediaSessionCompat? = null
    private lateinit var stateBuilder: PlaybackStateCompat.Builder
    private lateinit var audioBridge: AudioSessionBridge
    private val serviceJob = SupervisorJob()
    private val serviceScope = CoroutineScope(Dispatchers.Main + serviceJob)
    
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service created")
        
        // Initialize audio bridge
        audioBridge = AudioSessionBridge.getInstance(this)
        
        // Try to discover the existing MediaSession created by just_audio_background
        val discovered = audioBridge.discoverMediaSession()
        if (discovered && audioBridge.hasDirectControl()) {
            Log.i(TAG, "Using discovered MediaSession for Android Auto")
            sessionToken = audioBridge.getConnectedSessionToken()
        } else {
            Log.w(TAG, "Falling back to local MediaSession instance")
            val session = MediaSessionCompat(this, TAG)
            mediaSession = session
            val sessionIntent = packageManager?.getLaunchIntentForPackage(packageName)
            val sessionActivityPendingIntent = PendingIntent.getActivity(
                this@WiddleReaderMediaService,
                0,
                sessionIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            session.setSessionActivity(sessionActivityPendingIntent)
            session.setCallback(MediaSessionCallback())

            stateBuilder = PlaybackStateCompat.Builder()
                .setActions(getAllowedActions())
                .setState(PlaybackStateCompat.STATE_NONE, 0, 1.0f)
            session.setPlaybackState(stateBuilder.build())
            session.isActive = true

            sessionToken = session.sessionToken
            audioBridge.setTargetSessionForUpdates(session)
            Log.d(TAG, "Local MediaSession initialized for Android Auto")
        }
    }
    
    override fun onDestroy() {
        serviceJob.cancel()
        mediaSession?.let { session ->
            session.isActive = false
            session.release()
        }
        super.onDestroy()
    }
    
    override fun onGetRoot(
        clientPackageName: String,
        clientUid: Int,
        rootHints: Bundle?
    ): BrowserRoot? {
        Log.d(TAG, """
            |=== MediaBrowserService Connection Request ===
            |Package: $clientPackageName
            |UID: $clientUid
            |Hints: $rootHints
            |Android Auto Hint: ${rootHints?.getBoolean("android.service.media.extra.BROWSER_SERVICE_EXTRAS")}
            |===============================================
        """.trimMargin())
        
        // Validate client (Android Auto, Google Play Services, etc.)
        if (!isValidPackage(clientPackageName, clientUid)) {
            Log.e(TAG, "🚫 REJECTED: Package '$clientPackageName' (UID: $clientUid) not authorized")
            return null
        }
        
        // Try to discover and connect to the app's MediaSession for direct control
        if (!audioBridge.hasDirectControl()) {
            Log.d(TAG, "🔍 Attempting to discover MediaSession...")
            val discovered = audioBridge.discoverMediaSession()
            if (discovered) {
                Log.i(TAG, "✅ MediaSession discovered and connected for direct control")
            } else {
                Log.w(TAG, "⚠️ No MediaSession discovered, will use SharedPreferences fallback")
            }
        } else {
            Log.d(TAG, "✅ MediaSession already connected")
        }
        
        Log.i(TAG, "✅ ACCEPTED: Returning root ID '$ROOT_ID' to $clientPackageName")
        return BrowserRoot(ROOT_ID, null)
    }
    
    override fun onLoadChildren(
        parentId: String,
        result: Result<MutableList<MediaBrowserCompat.MediaItem>>
    ) {
        result.detach()
        
        serviceScope.launch {
            try {
                Log.d(TAG, "📦 onLoadChildren -> parentId=$parentId")
                val children = withContext(Dispatchers.IO) {
                    loadChildrenForParent(parentId)
                }
                result.sendResult(children.toMutableList())
            } catch (e: Exception) {
                Log.e(TAG, "Error loading children", e)
                result.sendResult(mutableListOf())
            }
        }
    }
    
    override fun onSearch(
        query: String,
        extras: Bundle?,
        result: Result<MutableList<MediaBrowserCompat.MediaItem>>
    ) {
        result.detach()
        
        serviceScope.launch {
            try {
                val results = withContext(Dispatchers.IO) {
                    performSearch(query)
                }
                result.sendResult(results.toMutableList())
            } catch (e: Exception) {
                result.sendResult(mutableListOf())
            }
        }
    }
    
    private suspend fun loadChildrenForParent(parentId: String): List<MediaBrowserCompat.MediaItem> {
        return when {
            parentId == ROOT_ID -> buildRootItems()
            parentId == "section_recent" -> buildRecentItems()
            parentId == "section_all" -> buildAllAudiobooksItems()
            parentId.startsWith("book_") -> buildChaptersForBook(parentId)
            else -> emptyList()
        }
    }
    
    private fun buildRootItems(): List<MediaBrowserCompat.MediaItem> {
        Log.d(TAG, "🏗️ BUILD: Building root items for Android Auto")
        val audiobooks = audioBridge.loadAudiobooks()
        
        if (audiobooks.isEmpty()) {
            return listOf(
                createBrowsableItem(
                    "empty",
                    "No Audiobooks",
                    "Add audiobooks in the app"
                )
            )
        }

        val items = mutableListOf<MediaBrowserCompat.MediaItem>()

        // 1. Resume Item (Top Priority)
        val audiobooksWithTimestamp = audiobooks.filter { (it["lastPlayed"] as? Number)?.toLong() ?: 0L > 0 }
        val currentBook = audiobooksWithTimestamp.maxByOrNull { (it["lastPlayed"] as? Number)?.toLong() ?: 0L }
            ?: audiobooks.firstOrNull()

        currentBook?.let { book ->
            val title = book["title"] as? String ?: "Resume Audiobook"
            val author = book["author"] as? String ?: ""
            val bookId = book["id"] as? String ?: ""
            val coverArt = book["coverArt"] as? String
            
            items += createPlayableItem(
                "resume_$bookId",
                "▶ Resume: $title",
                author,
                coverArt
            )
        }

        // 2. Recent (Simplified)
        items += createBrowsableItem(
            "section_recent",
            "Recent",
            "Recently played books"
        )

        // 3. Library (A-Z)
        items += createBrowsableItem(
            "section_all",
            "Library",
            "All audiobooks A-Z"
        )

        return items
    }
    
    private fun buildRecentItems(): List<MediaBrowserCompat.MediaItem> {
        return audioBridge.loadAudiobooks()
            .filter { (it["lastPlayed"] as? Number)?.toLong() ?: 0L > 0 }
            .sortedByDescending { (it["lastPlayed"] as? Number)?.toLong() ?: 0L }
            .take(MAX_RECENT_ITEMS)
            .map { createAudiobookMediaItem(it) }
    }
    

    
    private fun buildAllAudiobooksItems(): List<MediaBrowserCompat.MediaItem> {
        return audioBridge.loadAudiobooks()
            .sortedBy { (it["title"] as? String ?: "").lowercase() }
            .take(MAX_BROWSE_ITEMS)
            .map { createAudiobookMediaItem(it) }
    }
    
    private fun buildChaptersForBook(bookId: String): List<MediaBrowserCompat.MediaItem> {
        val audiobookId = bookId.removePrefix("book_")
        val audiobook = audioBridge.loadAudiobooks()
            .find { it["id"] as? String == audiobookId } ?: return emptyList()
        
        @Suppress("UNCHECKED_CAST")
        val chapters = audiobook["chapters"] as? List<Map<String, Any>> ?: return emptyList()
        
        return chapters.mapIndexed { index, chapter ->
            createPlayableChapterItem(chapter, audiobook, index)
        }
    }
    
    private fun performSearch(query: String): List<MediaBrowserCompat.MediaItem> {
        val lowerQuery = query.lowercase()
        return audioBridge.loadAudiobooks()
            .filter {
                val title = (it["title"] as? String ?: "").lowercase()
                val author = (it["author"] as? String ?: "").lowercase()
                title.contains(lowerQuery) || author.contains(lowerQuery)
            }
            .take(MAX_BROWSE_ITEMS)
            .map { createAudiobookMediaItem(it) }
    }
    
    private fun createPlayableItem(
        id: String, 
        title: String, 
        subtitle: String,
        coverArtSource: String?
    ): MediaBrowserCompat.MediaItem {
        val descriptionBuilder = MediaDescriptionCompat.Builder()
            .setMediaId(id)
            .setTitle(truncate(title, 40))
            .setSubtitle(truncate(subtitle, 60))
        
        // Add cover art if available - use larger size for single items (like Resume)
        coverArtSource?.let {
            loadBitmap(it, 200, 200)?.let { bitmap -> 
                descriptionBuilder.setIconBitmap(bitmap) 
            }
        }
        
        val description = descriptionBuilder.build()
        return MediaBrowserCompat.MediaItem(description, MediaBrowserCompat.MediaItem.FLAG_PLAYABLE)
    }
    
    private fun createBrowsableItem(
        id: String, 
        title: String, 
        subtitle: String
    ): MediaBrowserCompat.MediaItem {
        val description = MediaDescriptionCompat.Builder()
            .setMediaId(id)
            .setTitle(truncate(title, 40))
            .setSubtitle(truncate(subtitle, 60))
            .build()
        
        return MediaBrowserCompat.MediaItem(description, MediaBrowserCompat.MediaItem.FLAG_BROWSABLE)
    }
    
    private fun createAudiobookMediaItem(audiobook: Map<String, Any>): MediaBrowserCompat.MediaItem {
        val id = audiobook["id"] as? String ?: ""
        val title = audiobook["title"] as? String ?: "Unknown"
        val author = audiobook["author"] as? String ?: "Unknown Author"
        
        val descriptionBuilder = MediaDescriptionCompat.Builder()
            .setMediaId("book_$id")
            .setTitle(truncate(title, 40))
            .setSubtitle(truncate(author, 60))
        
        // Use small thumbnail for lists to avoid TransactionTooLargeException
        (audiobook["coverArt"] as? String)?.let {
            loadBitmap(it, 80, 80)?.let { bitmap -> descriptionBuilder.setIconBitmap(bitmap) }
        }
        
        return MediaBrowserCompat.MediaItem(
            descriptionBuilder.build(),
            MediaBrowserCompat.MediaItem.FLAG_BROWSABLE
        )
    }
    
    private fun createPlayableChapterItem(
        chapter: Map<String, Any>,
        audiobook: Map<String, Any>,
        index: Int
    ): MediaBrowserCompat.MediaItem {
        val chapterId = chapter["id"] as? String ?: ""
        val chapterTitle = chapter["title"] as? String ?: "Chapter ${index + 1}"
        val bookTitle = audiobook["title"] as? String ?: "Unknown"
        
        val descriptionBuilder = MediaDescriptionCompat.Builder()
            .setMediaId("chapter_$chapterId")
            .setTitle(truncate(chapterTitle, 40))
            .setSubtitle(truncate(bookTitle, 60))
            .setMediaUri(Uri.parse(chapterId))
        
        // Use small thumbnail for lists
        (audiobook["coverArt"] as? String)?.let {
            loadBitmap(it, 80, 80)?.let { bitmap -> descriptionBuilder.setIconBitmap(bitmap) }
        }
        
        return MediaBrowserCompat.MediaItem(
            descriptionBuilder.build(),
            MediaBrowserCompat.MediaItem.FLAG_PLAYABLE
        )
    }
    
    private fun loadBitmap(source: String, reqWidth: Int, reqHeight: Int): Bitmap? {
        return try {
            // Check if it's a file path
            if (source.startsWith("/") || source.startsWith("file://")) {
                val filePath = if (source.startsWith("file://")) Uri.parse(source).path else source
                val options = BitmapFactory.Options().apply {
                    inJustDecodeBounds = true
                }
                BitmapFactory.decodeFile(filePath, options)
                
                options.inSampleSize = calculateInSampleSize(options, reqWidth, reqHeight)
                options.inJustDecodeBounds = false
                
                return BitmapFactory.decodeFile(filePath, options)
            }
            
            // Fallback to Base64
            val bytes = Base64.decode(source, Base64.DEFAULT)
            
            // First decode with inJustDecodeBounds=true to check dimensions
            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
            
            // Calculate inSampleSize
            options.inSampleSize = calculateInSampleSize(options, reqWidth, reqHeight)
            
            // Decode bitmap with inSampleSize set
            options.inJustDecodeBounds = false
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
        } catch (e: Exception) {
            Log.e(TAG, "Error loading bitmap: ${e.message}")
            null
        }
    }
    
    private fun calculateInSampleSize(options: BitmapFactory.Options, reqWidth: Int, reqHeight: Int): Int {
        // Raw height and width of image
        val (height: Int, width: Int) = options.run { outHeight to outWidth }
        var inSampleSize = 1

        if (height > reqHeight || width > reqWidth) {
            val halfHeight: Int = height / 2
            val halfWidth: Int = width / 2

            // Calculate the largest inSampleSize value that is a power of 2 and keeps both
            // height and width larger than the requested height and width.
            while (halfHeight / inSampleSize >= reqHeight && halfWidth / inSampleSize >= reqWidth) {
                inSampleSize *= 2
            }
        }

        return inSampleSize
    }
    
    private fun truncate(text: String, maxLength: Int): String {
        return if (text.length > maxLength) text.take(maxLength - 3) + "..." else text
    }
    
    private fun isValidPackage(packageName: String, clientUid: Int): Boolean {
        // Allow system-level packages (Android Auto on automotive OS runs as system)
        if (clientUid < 10000) {
            Log.d(TAG, "✅ Allowing system-level access for UID $clientUid")
            return true
        }
        
        // Comprehensive whitelist for Android Auto and related services
        val validPrefixes = listOf(
            // Google Android Auto (primary)
            "com.google.android.projection.gearhead",
            "com.google.android.apps.automotive",
            
            // Google services
            "com.google.android.gms",
            "com.google.android.googlequicksearchbox", // Voice search
            
            // Android system
            "com.android.car",
            "com.android.systemui",
            "android", // System processes
            
            // OEM Android Auto variants
            "com.samsung.android.auto",
            "com.ford.sync", // Ford SYNC
            "com.toyota.entune", // Toyota Entune
            "com.fca.uconnect", // Chrysler/Jeep/Dodge uConnect
            
            // Testing and development
            packageName, // Allow self-connection for testing
            "com.example" // Desktop Head Unit (DHU) simulator
        )
        
        val isValid = validPrefixes.any { packageName.startsWith(it) }
        
        if (!isValid) {
            Log.w(TAG, "⚠️ Unknown package attempting connection: $packageName (UID: $clientUid)")
            // TEMPORARY DEBUG: Allow all packages to identify the actual client
            Log.w(TAG, "🔧 DEBUG MODE: Allowing connection anyway for testing")
            return true  // REMOVE THIS AFTER IDENTIFYING THE CLIENT PACKAGE
        } else {
            Log.d(TAG, "✅ Package validated: $packageName")
        }
        
        return isValid
    }
    
    private fun getAllowedActions(): Long {
        return PlaybackStateCompat.ACTION_PLAY or
                PlaybackStateCompat.ACTION_PAUSE or
                PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                PlaybackStateCompat.ACTION_SEEK_TO or
                PlaybackStateCompat.ACTION_PLAY_FROM_MEDIA_ID or
                PlaybackStateCompat.ACTION_PLAY_FROM_SEARCH
    }
    
    /**
     * MediaSession callback - uses AudioSessionBridge for direct control
     */
    private inner class MediaSessionCallback : MediaSessionCompat.Callback() {
        
        override fun onPlay() {
            audioBridge.executeCommand("play")
        }
        
        override fun onPause() {
            audioBridge.executeCommand("pause")
        }
        
        override fun onSkipToNext() {
            audioBridge.executeCommand("skipToNext")
        }
        
        override fun onSkipToPrevious() {
            audioBridge.executeCommand("skipToPrevious")
        }
        
        override fun onSeekTo(pos: Long) {
            audioBridge.executeCommand("seekTo", mapOf("position" to pos))
        }
        
        override fun onPlayFromMediaId(mediaId: String?, extras: Bundle?) {
            Log.d(TAG, "🎯 onPlayFromMediaId called with mediaId: $mediaId")
            mediaId?.let {
                when {
                    it.startsWith("resume_") -> {
                        // Extract book ID and play from last position
                        val bookId = it.removePrefix("resume_")
                        Log.d(TAG, "▶️ Resume button tapped - extracting bookId: $bookId")
                        Log.d(TAG, "📤 Calling audioBridge.executeCommand(playFromMediaId, book_$bookId)")
                        val result = audioBridge.executeCommand("playFromMediaId", mapOf("mediaId" to "book_$bookId"))
                        Log.d(TAG, "✅ Command execution returned: $result")
                    }
                    else -> {
                        Log.d(TAG, "📤 Calling audioBridge.executeCommand(playFromMediaId, $it)")
                        val result = audioBridge.executeCommand("playFromMediaId", mapOf("mediaId" to it))
                        Log.d(TAG, "✅ Command execution returned: $result")
                    }
                }
            } ?: Log.w(TAG, "⚠️ onPlayFromMediaId called with null mediaId")
        }
        
        override fun onPlayFromSearch(query: String?, extras: Bundle?) {
            query?.let {
                audioBridge.executeCommand("playFromSearch", mapOf("query" to it))
            }
        }
    }
}
