package com.widdlereader.app

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Parcel
import android.provider.Settings
import android.util.Log
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import android.support.v4.media.session.MediaSessionCompat

class MainActivity: AudioServiceActivity() {
    private val LICENSING_CHANNEL = "com.widdlereader.app/licensing"
    private val ANDROID_AUTO_CHANNEL = "com.widdlereader.app/android_auto"
    private val AUDIO_BRIDGE_CHANNEL = "com.widdlereader.app/audio_bridge"
    private lateinit var preferences: SharedPreferences
    
    companion object {
        private const val TAG = "MainActivity"
        private const val PREFS_FILE = "widdle_reader_license_prefs"
        private const val PREF_LICENSE_KEY = "license_key"
        private const val PREF_DEVICE_ID_KEY = "device_id_key"
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Init preferences
        preferences = applicationContext.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
        
        // Setup licensing channel
        setupLicensingChannel(flutterEngine)
        
        // Setup Android Auto channel
        setupAndroidAutoChannel(flutterEngine)
        
        // Setup Audio Bridge channel for MediaSession registration
        setupAudioBridgeChannel(flutterEngine)
    }
    
    private fun setupLicensingChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LICENSING_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initLicensing" -> {
                    try {
                        val publicKey = call.argument<String>("publicKey") ?: ""
                        if (publicKey.isEmpty() || publicKey == "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxP06zQm9di3ARFd9pI/akn+ZDoR44zYawe3qwp7I/S3eCjJVQcNzwANUw/J5J6bSWGx4dF+E37DoWPcQOKEJtjWXd97Xb+8kkRctEqRTQuLsAAa8lZU6vY2rjhR5Uuw2z176Xfg1pP17SOBWUcC0HcAs8UM7DmIxlKqqFTtEUWrUF9YaiVHDeC+ejeoUeNNDEdxWKP9bP2+hN6EKe+IdCYnCIE36ut941qANaQ0WwyZQJdIE7+KxmI7QzJJwvRLmBlONIFsuFnntV2jeyDknuMVUfoaCkd9oi+qBSKJbmpp1rTEbHts/vMiXGQp/w6okgdmIIl4FUU0sKMIEPtEwRQIDAQAB") {
                            Log.e(TAG, "License key not provided")
                            result.error("INVALID_KEY", "Public key is empty or not set", null)
                            return@setMethodCallHandler
                        }
                        
                        // Store the public key for later use
                        preferences.edit().putString("public_key", publicKey).apply()
                        result.success("success")
                    } catch (e: Exception) {
                        Log.e(TAG, "Error initializing licensing: ${e.message}")
                        result.error("INIT_ERROR", "Failed to initialize licensing: ${e.message}", null)
                    }
                }
                "checkLicense" -> {
                    // For development purposes, we'll just simulate license verification
                    // For production, this would connect to Google Play
                    val deviceId = getDeviceId(context)
                    Log.d(TAG, "License check for device: $deviceId")
                    
                    // In production, this would verify against Google Play and handle the response
                    val licenseResult = "LICENSED"
                    storeResult(licenseResult, deviceId)
                    
                    // Return success to the Dart side
                    Handler(Looper.getMainLooper()).post {
                        result.success(licenseResult)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    private fun setupAndroidAutoChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ANDROID_AUTO_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    try {
                        Log.d(TAG, "Android Auto channel initialized")
                        result.success(mapOf(
                            "success" to true,
                            "platform" to "android"
                        ))
                    } catch (e: Exception) {
                        Log.e(TAG, "Error initializing Android Auto channel: ${e.message}")
                        result.error("INIT_ERROR", e.message, null)
                    }
                }
                "getStatus" -> {
                    try {
                        // Return Android Auto connection status
                        val status = mapOf(
                            "available" to true,
                            "connected" to isAndroidAutoConnected(),
                            "version" to Build.VERSION.SDK_INT
                        )
                        result.success(status)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error getting Android Auto status: ${e.message}")
                        result.error("STATUS_ERROR", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    private fun isAndroidAutoConnected(): Boolean {
        // Check if Android Auto is currently connected
        // This is a simplified check - in production, you might want more sophisticated detection
        return try {
            val uiMode = resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_TYPE_MASK
            uiMode == android.content.res.Configuration.UI_MODE_TYPE_CAR
        } catch (e: Exception) {
            false
        }
    }
    
    private fun setupAudioBridgeChannel(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_BRIDGE_CHANNEL)
        val bridge = com.widdlereader.app.auto.AudioSessionBridge.getInstance(applicationContext)
        bridge.setCommandChannel(channel)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "registerMediaSession" -> {
                    try {
                        val tokenBytes = call.argument<ByteArray>("token")
                        if (tokenBytes != null) {
                            val parcel = Parcel.obtain()
                            try {
                                parcel.unmarshall(tokenBytes, 0, tokenBytes.size)
                                parcel.setDataPosition(0)
                                val token = MediaSessionCompat.Token.CREATOR.createFromParcel(parcel)
                                bridge.registerSessionToken(token)
                                result.success(mapOf(
                                    "success" to true,
                                    "hasDirectControl" to bridge.hasDirectControl()
                                ))
                            } finally {
                                parcel.recycle()
                            }
                        } else {
                            result.error("INVALID_TOKEN", "Token bytes missing", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error registering MediaSession: ${e.message}")
                        result.error("REGISTER_ERROR", e.message, null)
                    }
                }
                "registerServiceSession" -> {
                    try {
                        val tokenBytes = call.argument<ByteArray>("token")
                        if (tokenBytes != null) {
                            val parcel = Parcel.obtain()
                            try {
                                parcel.unmarshall(tokenBytes, 0, tokenBytes.size)
                                parcel.setDataPosition(0)
                                val token = MediaSessionCompat.Token.CREATOR.createFromParcel(parcel)
                                bridge.registerSessionToken(token)
                                result.success(true)
                            } finally {
                                parcel.recycle()
                            }
                        } else {
                            result.error("INVALID_TOKEN", "Token bytes missing", null)
                        }
                    } catch (e: Exception) {
                        result.error("REGISTER_ERROR", e.message, null)
                    }
                }
                "updateMetadata" -> {
                    try {
                        bridge.updateMetadata(
                            mediaId = call.argument<String>("mediaId"),
                            title = call.argument<String>("title") ?: "Unknown",
                            artist = call.argument<String>("artist") ?: "Unknown Artist",
                            album = call.argument<String>("album") ?: "",
                            duration = call.argument<Number>("duration")?.toLong() ?: 0L,
                            artUri = call.argument<String>("artUri"),
                            displayTitle = call.argument<String>("displayTitle"),
                            displaySubtitle = call.argument<String>("displaySubtitle"),
                            displayDescription = call.argument<String>("displayDescription"),
                            chapterTitle = call.argument<String>("chapterTitle")
                        )
                        Log.d(TAG, "Updated MediaSession metadata from Flutter")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error updating metadata: ${e.message}")
                        result.error("METADATA_ERROR", e.message, null)
                    }
                }
                "updatePlaybackState" -> {
                    try {
                        bridge.updatePlaybackState(
                            position = call.argument<Number>("position")?.toLong() ?: 0L,
                            isPlaying = call.argument<Boolean>("isPlaying") ?: false,
                            speed = call.argument<Double>("speed")?.toFloat() ?: 1f,
                            hasNext = call.argument<Boolean>("hasNext") ?: true,
                            hasPrevious = call.argument<Boolean>("hasPrevious") ?: true
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error updating playback state: ${e.message}")
                        result.error("STATE_ERROR", e.message, null)
                    }
                }
                "refreshPlaybackState" -> {
                    try {
                        bridge.updatePlaybackState(
                            position = call.argument<Int>("position")?.toLong() ?: 0L,
                            isPlaying = call.argument<Boolean>("isPlaying") ?: false,
                            speed = call.argument<Double>("speed")?.toFloat() ?: 1f,
                            hasNext = call.argument<Boolean>("hasNext") ?: true,
                            hasPrevious = call.argument<Boolean>("hasPrevious") ?: true
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STATE_ERROR", e.message, null)
                    }
                }
                "mediaSessionCommand" -> {
                    val action = call.argument<String>("action")
                    val params = call.argument<Map<String, Any>>("params")
                    if (action != null) {
                        bridge.onFlutterCommand(action, params)
                        result.success(true)
                    } else {
                        result.error("INVALID_COMMAND", "Missing action", null)
                    }
                }
                "hasDirectControl" -> {
                    try {
                        result.success(bridge.hasDirectControl())
                    } catch (e: Exception) {
                        result.error("QUERY_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    
    private fun storeResult(result: String, deviceId: String) {
        preferences.edit().apply {
            putString(PREF_LICENSE_KEY, result)
            putString(PREF_DEVICE_ID_KEY, deviceId)
            apply()
        }
    }
    
    // Generate a device ID based on device attributes
    private fun getDeviceId(context: Context): String {
        val androidId = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
        val deviceInfo = arrayOf(
            androidId,
            Build.DEVICE,
            Build.MODEL,
            Build.PRODUCT,
            Build.BRAND
        ).joinToString("_")
        
        // Hash the device info for privacy
        return sha256(deviceInfo)
    }
    
    // Generate SHA-256 hash
    private fun sha256(input: String): String {
        val bytes = input.toByteArray()
        val md = MessageDigest.getInstance("SHA-256")
        val digest = md.digest(bytes)
        return digest.fold("") { str, it -> str + "%02x".format(it) }
    }
} 