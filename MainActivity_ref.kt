package com.widdlereader.app

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity: AudioServiceActivity() {
    private val CHANNEL = "com.widdlereader.app/licensing"
    private lateinit var preferences: SharedPreferences
    
    companion object {
        private const val TAG = "LicenseActivity"
        private const val PREFS_FILE = "widdle_reader_license_prefs"
        private const val PREF_LICENSE_KEY = "license_key"
        private const val PREF_DEVICE_ID_KEY = "device_id_key"
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Init preferences
        preferences = applicationContext.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
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