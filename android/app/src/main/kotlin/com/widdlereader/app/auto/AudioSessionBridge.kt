package com.widdlereader.app.auto

import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.session.MediaSessionManager
import android.net.Uri
import android.os.Build
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaControllerCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import androidx.media.MediaBrowserServiceCompat
import com.google.gson.Gson
import java.io.File
import io.flutter.plugin.common.MethodChannel
import android.os.Parcel

/**
 * Bridge between Android Auto MediaBrowserService and the app's audio playback
 * 
 * This solves the architectural issue of having two separate audio systems by:
 * 1. Providing direct MediaSession control (no polling delay)
 * 2. Maintaining compatibility with existing SimpleAudioService
 * 3. Offering both direct control and fallback mechanisms
 */
class AudioSessionBridge(private val context: Context) {
    
    companion object {
        private const val TAG = "AudioSessionBridge"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val PREFS_PREFIX = "flutter.android_auto_"
        
        @Volatile
        private var instance: AudioSessionBridge? = null
        
        fun getInstance(context: Context): AudioSessionBridge {
            return instance ?: synchronized(this) {
                instance ?: AudioSessionBridge(context.applicationContext).also { instance = it }
            }
        }
    }
    
    private val preferences: SharedPreferences = 
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val gson = Gson()
    
    // Direct media controller access (when available)
    private var mediaController: MediaControllerCompat? = null
    private var mediaSession: MediaSessionCompat? = null
    private var targetSessionForUpdates: MediaSessionCompat? = null
    private var serviceSessionToken: MediaSessionCompat.Token? = null
    private var commandChannel: MethodChannel? = null

    fun setCommandChannel(channel: MethodChannel) {
        commandChannel = channel
    }

    fun getConnectedSessionToken(): MediaSessionCompat.Token? {
        return serviceSessionToken
    }

    /**
     * Register a MediaSession for direct control
     * Call this from your main audio service (if you have one separate from MediaBrowserService)
     */
    fun registerMediaSession(session: MediaSessionCompat) {
        Log.d(TAG, "Registering MediaSession for direct control")
        this.mediaSession = session
        this.serviceSessionToken = session.sessionToken
        this.mediaController = MediaControllerCompat(context, session)
    }

    fun registerSessionToken(token: MediaSessionCompat.Token) {
        Log.d(TAG, "Registering MediaSession token for direct control")
        this.mediaSession = null
        this.serviceSessionToken = token
        
        // ENHANCEMENT #9: Protected MediaController construction
        try {
            this.mediaController = MediaControllerCompat(context, token)
            Log.d(TAG, "✅ MediaController created successfully")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to create MediaController: ${e.message}", e)
            this.mediaController = null
            // Don't throw - allow fallback to work
        }
    }
    
    /**
     * Discover and connect to the app's active MediaSession
     * This finds the MediaSession created by just_audio or audio_service
     * 
     * NOTE: This won't work without BIND_NOTIFICATION_LISTENER_SERVICE permission,
     * which normal apps can't get. This method always returns false, and we rely
     * on the fallback mechanism (local MediaSession + SharedPreferences bridge).
     * 
     * The fallback works by:
     * 1. WiddleReaderMediaService creates its own MediaSession
     * 2. Flutter sends updates via method channel to AudioSessionBridge
     * 3. AudioSessionBridge updates the MediaSession that Android Auto sees
     * 4. Commands from Android Auto → MediaSession callbacks → SharedPreferences → Flutter
     */
    fun discoverMediaSession(): Boolean {
        Log.d(TAG, "MediaSession discovery skipped - using fallback architecture")
        Log.d(TAG, "Fallback: WiddleReaderMediaService session + SharedPreferences bridge")
        
        // Always return false to force fallback path
        // The fallback architecture is the proper solution for this app
        return false
    }
    
    /**
     * Set target MediaSession for metadata/state updates only (no control)
     * Use this to avoid recursion when the MediaBrowserService needs updates
     */
    fun setTargetSessionForUpdates(session: MediaSessionCompat) {
        Log.d(TAG, "Setting target MediaSession for updates only")
        this.targetSessionForUpdates = session
    }
    
    /**
     * Execute playback command with direct control fallback
     * Priority: Direct MediaSession > SharedPreferences command
     */
    fun executeCommand(action: String, params: Map<String, Any>? = null, allowDirect: Boolean = true): Boolean {
        return try {
            val direct = mediaController
            if (allowDirect && direct != null && direct.packageName == context.packageName) {
                executeDirectCommand(action, params)
            } else {
                sendCommandToFlutter(action, params)
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error executing command: $action", e)
            false
        }
    }

    fun onFlutterCommand(action: String, params: Map<String, Any>?) {
        val direct = mediaController
        if (direct != null && direct.packageName == context.packageName) {
            executeDirectCommand(action, params)
        } else {
            executeLegacyCommand(action, params)
        }
    }

    private fun sendCommandToFlutter(action: String, params: Map<String, Any>? = null) {
        val channel = commandChannel
        if (channel != null) {
            try {
                channel.invokeMethod(
                    "mediaSessionCommand",
                    mapOf(
                        "action" to action,
                        "params" to (params ?: emptyMap<String, Any>())
                    )
                )
                return
            } catch (e: Exception) {
                Log.e(TAG, "Error sending command to Flutter", e)
            }
        }
        
        Log.w(TAG, "Command channel not available; attempting to wake up Flutter app")
        
        // If we are here, Flutter is likely dead or not connected.
        // We need to start the app to handle the media command.
        try {
            val packageManager = context.packageManager
            val intent = packageManager.getLaunchIntentForPackage(context.packageName)
            if (intent != null) {
                intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                // Add extra to tell Flutter to handle this command on start
                intent.putExtra("background_mode", "audio_service_wake")
                context.startActivity(intent)
                Log.i(TAG, "🚀 Launched app to handle background media command")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch app for background playback", e)
        }

        // Still write to legacy prefs just in case
        executeLegacyCommand(action, params)
    }
    
    /**
     * Direct MediaController execution (preferred method)
     */
    private fun executeDirectCommand(action: String, params: Map<String, Any>?) {
        val transportControls = mediaController?.transportControls ?: return
        
        when (action) {
            "play" -> transportControls.play()
            "pause" -> transportControls.pause()
            "skipToNext" -> transportControls.skipToNext()
            "skipToPrevious" -> transportControls.skipToPrevious()
            "seekTo" -> {
                val position = (params?.get("position") as? Number)?.toLong() ?: return
                transportControls.seekTo(position)
            }
            "setSpeed" -> {
                val speed = (params?.get("speed") as? Number)?.toFloat() ?: return
                transportControls.setPlaybackSpeed(speed)
            }
            "playFromMediaId" -> {
                val mediaId = params?.get("mediaId") as? String ?: return
                transportControls.playFromMediaId(mediaId, null)
            }
            "playFromSearch" -> {
                val query = params?.get("query") as? String ?: return
                transportControls.playFromSearch(query, null)
            }
        }
        
        Log.d(TAG, "Executed direct command: $action")
    }
    
    /**
     * Legacy SharedPreferences execution (fallback)
     */
    private fun executeLegacyCommand(action: String, params: Map<String, Any>?) {
        val command = mapOf(
            "action" to action,
            "params" to (params ?: emptyMap<String, Any>()),
            "timestamp" to System.currentTimeMillis()
        )
        
        val commandJson = gson.toJson(command)
        val key = "${PREFS_PREFIX}playback_command"
        
        preferences.edit()
            .putString(key, commandJson)
            .apply()
        
        Log.d(TAG, "📝 WRITE_CMD: Wrote to key: $key")
        Log.d(TAG, "📝 WRITE_CMD: Data: $commandJson")
        Log.d(TAG, "✅ Legacy command written successfully: $action")
    }
    
    /**
     * Get current playback state
     */
    fun getPlaybackState(): PlaybackStateCompat? {
        return mediaController?.playbackState
    }
    
    /**
     * Check if direct control is available
     */
    fun hasDirectControl(): Boolean {
        return mediaController != null
    }
    
    /**
     * Load audiobooks from SharedPreferences
     */
    fun loadAudiobooks(): List<Map<String, Any>> {
        val key = "${PREFS_PREFIX}audiobooks"
        val json = preferences.getString(key, null)
        
        if (json == null) {
            Log.w(TAG, "📖 LOAD: No audiobooks found in SharedPreferences key: $key")
            return emptyList()
        }
        
        Log.d(TAG, "📖 LOAD: Reading from key: $key")
        Log.d(TAG, "📖 LOAD: Data length: ${json.length} chars")
        Log.d(TAG, "📖 LOAD: First 300 chars: ${if (json.length > 300) json.substring(0, 300) else json}...")
        
        return try {
            @Suppress("UNCHECKED_CAST")
            val rawList = gson.fromJson(json, List::class.java) as? List<*>
            val audiobooks = rawList?.filterIsInstance<Map<String, Any>>() ?: emptyList()
            
            Log.d(TAG, "✅ LOAD: Parsed ${audiobooks.size} audiobooks successfully")
            
            // Log first audiobook for debugging
            if (audiobooks.isNotEmpty()) {
                val first = audiobooks.first()
                Log.d(TAG, "📚 First book: id=${first["id"]}, title=${first["title"]}, lastPlayed=${first["lastPlayed"]}")
            }
            
            audiobooks
        } catch (e: Exception) {
            Log.e(TAG, "❌ LOAD: Error loading audiobooks", e)
            emptyList()
        }
    }
    
    /**
     * Load tags from SharedPreferences
     */
    fun loadTags(): List<Map<String, Any>> {
        val json = preferences.getString("${PREFS_PREFIX}tags", null) ?: return emptyList()
        
        return try {
            @Suppress("UNCHECKED_CAST")
            val rawList = gson.fromJson(json, List::class.java) as? List<*>
            rawList?.filterIsInstance<Map<String, Any>>() ?: emptyList()
        } catch (e: Exception) {
            Log.e(TAG, "Error loading tags", e)
            emptyList()
        }
    }
    
    /**
     * Load audiobook-tag assignments
     */
    fun loadAudiobookTags(): Map<String, List<String>> {
        val json = preferences.getString("${PREFS_PREFIX}audiobook_tags", null) ?: return emptyMap()
        
        return try {
            @Suppress("UNCHECKED_CAST")
            val rawMap = gson.fromJson(json, Map::class.java) as? Map<*, *>
            rawMap?.entries?.mapNotNull { (key, value) ->
                val k = key as? String
                val v = (value as? List<*>)?.filterIsInstance<String>()
                if (k != null && v != null) k to v else null
            }?.toMap() ?: emptyMap()
        } catch (e: Exception) {
            Log.e(TAG, "Error loading audiobook tags", e)
            emptyMap()
        }
    }
    
    /**
     * Update MediaSession metadata (title, author, cover art, duration)
     * Call this when a new book/chapter loads
     */
    fun updateMetadata(
        mediaId: String?,
        title: String,
        artist: String,
        album: String,
        duration: Long,
        artUri: String? = null,
        displayTitle: String? = null,
        displaySubtitle: String? = null,
        displayDescription: String? = null,
        chapterTitle: String? = null
    ) {
        val session = targetSessionForUpdates ?: mediaSession
        session?.let {
            try {
                val metadataBuilder = MediaMetadataCompat.Builder()
                    .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
                    .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
                    .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, album)
                    .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)
                    .putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ARTIST, artist)
                    .putString(MediaMetadataCompat.METADATA_KEY_AUTHOR, artist)
                    .putString(MediaMetadataCompat.METADATA_KEY_WRITER, artist)

                val resolvedDisplayTitle = displayTitle?.takeIf { it.isNotBlank() } ?: title
                metadataBuilder.putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_TITLE, resolvedDisplayTitle)

                displaySubtitle?.takeIf { it.isNotBlank() }?.let { value ->
                    metadataBuilder.putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_SUBTITLE, value)
                }

                displayDescription?.takeIf { it.isNotBlank() }?.let { value ->
                    metadataBuilder.putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_DESCRIPTION, value)
                }

                chapterTitle?.takeIf { it.isNotBlank() }?.let { value ->
                    metadataBuilder.putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_SUBTITLE, value)
                }

                mediaId?.takeIf { it.isNotBlank() }?.let { value ->
                    metadataBuilder.putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, value)
                }
                
                // Load cover art if provided
                artUri?.let { uri ->
                    val artwork = loadArtwork(uri)
                    if (artwork != null) {
                        metadataBuilder.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, artwork)
                        metadataBuilder.putBitmap(MediaMetadataCompat.METADATA_KEY_ART, artwork)
                        metadataBuilder.putBitmap(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON, artwork)
                    }
                    metadataBuilder.putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, uri)
                    metadataBuilder.putString(MediaMetadataCompat.METADATA_KEY_ART_URI, uri)
                    metadataBuilder.putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON_URI, uri)
                }
                
                it.setMetadata(metadataBuilder.build())
                Log.d(TAG, "Updated metadata: title=$title | subtitle=${displaySubtitle ?: chapterTitle} | artist=$artist")
            } catch (e: Exception) {
                Log.e(TAG, "Error updating metadata", e)
            }
        } ?: Log.w(TAG, "Cannot update metadata - MediaSession not registered")
    }
    
    /**
     * Update playback state (position, playing/paused, speed)
     * Call this periodically during playback (every 1-2 seconds)
     */
    fun updatePlaybackState(
        position: Long,
        isPlaying: Boolean,
        speed: Float = 1.0f,
        hasNext: Boolean = true,
        hasPrevious: Boolean = true
    ) {
        val session = targetSessionForUpdates ?: mediaSession
        session?.let {
            try {
                val state = if (isPlaying) {
                    PlaybackStateCompat.STATE_PLAYING
                } else {
                    PlaybackStateCompat.STATE_PAUSED
                }
                
                // Define available actions
                var actions = PlaybackStateCompat.ACTION_PLAY_PAUSE or
                        PlaybackStateCompat.ACTION_SEEK_TO or
                        PlaybackStateCompat.ACTION_SET_PLAYBACK_SPEED
                
                if (isPlaying) {
                    actions = actions or PlaybackStateCompat.ACTION_PAUSE
                } else {
                    actions = actions or PlaybackStateCompat.ACTION_PLAY
                }
                
                if (hasNext) {
                    actions = actions or PlaybackStateCompat.ACTION_SKIP_TO_NEXT
                }
                
                if (hasPrevious) {
                    actions = actions or PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
                }
                
                val playbackState = PlaybackStateCompat.Builder()
                    .setState(state, position, speed)
                    .setActions(actions)
                    .build()
                
                it.setPlaybackState(playbackState)
                Log.d(TAG, "Updated playback state: pos=${position}ms, playing=$isPlaying, speed=$speed")
            } catch (e: Exception) {
                Log.e(TAG, "Error updating playback state", e)
            }
        } ?: Log.w(TAG, "Cannot update playback state - MediaSession not registered")
    }
    
    /**
     * Load artwork from file URI
     */
    /**
     * Load artwork from file URI with resizing to prevent TransactionTooLargeException
     */
    private fun loadArtwork(artUri: String): Bitmap? {
        return try {
            val targetSize = 320 // Robust size for notifications and widgets
            
            val filePath = when {
                artUri.startsWith("file://") -> Uri.parse(artUri).path
                artUri.startsWith("/") -> artUri
                else -> null
            }
            
            // Handle content:// URIs
            var finalBitmap: Bitmap? = null

            if (artUri.startsWith("content://")) {
                val uri = Uri.parse(artUri)
                context.contentResolver.openInputStream(uri)?.use { inputStream ->
                    val options = BitmapFactory.Options().apply {
                        inJustDecodeBounds = true
                    }
                    val bytes = inputStream.readBytes()
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
                    
                    options.inSampleSize = calculateInSampleSize(options, targetSize, targetSize)
                    options.inJustDecodeBounds = false
                    finalBitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
                }
            } else if (filePath != null) {
                val file = File(filePath)
                if (file.exists()) {
                    val options = BitmapFactory.Options().apply {
                        inJustDecodeBounds = true
                    }
                    BitmapFactory.decodeFile(file.absolutePath, options)
                    
                    options.inSampleSize = calculateInSampleSize(options, targetSize, targetSize)
                    options.inJustDecodeBounds = false
                    finalBitmap = BitmapFactory.decodeFile(file.absolutePath, options)
                }
            }

            if (finalBitmap != null) {
                // FORCE RESIZE: inSampleSize only supports powers of 2. 
                // We need to ensure it's actually small to avoid TransactionTooLargeException
                if (finalBitmap!!.width > targetSize + 20 || finalBitmap!!.height > targetSize + 20) {
                    val ratio = Math.min(targetSize.toDouble() / finalBitmap!!.width, targetSize.toDouble() / finalBitmap!!.height)
                    val width = (finalBitmap!!.width * ratio).toInt()
                    val height = (finalBitmap!!.height * ratio).toInt()
                    
                    Log.d(TAG, "Force resizing bitmap from ${finalBitmap!!.width}x${finalBitmap!!.height} to ${width}x${height}")
                    val scaled = Bitmap.createScaledBitmap(finalBitmap!!, width, height, true)
                    if (scaled != finalBitmap) {
                        finalBitmap!!.recycle()
                        finalBitmap = scaled
                    }
                }
                Log.d(TAG, "✅ Successfully loaded artwork: ${finalBitmap!!.width}x${finalBitmap!!.height} from $artUri")
                return finalBitmap
            } else {
                Log.w(TAG, "⚠️ Failed to decode artwork from: $artUri")
                return null
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error loading artwork from $artUri", e)
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
    
    /**
     * Get MediaSession token for external connections
     */
    fun getSessionToken(): MediaSessionCompat.Token? {
        return mediaSession?.sessionToken
    }
}

