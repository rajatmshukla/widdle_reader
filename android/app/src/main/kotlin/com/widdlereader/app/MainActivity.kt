package com.widdlereader.app

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Parcel
import android.provider.Settings
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import android.provider.DocumentsContract
import android.media.MediaMetadataRetriever
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import android.support.v4.media.session.MediaSessionCompat
import java.io.File

class MainActivity: AudioServiceActivity() {
    private val LICENSING_CHANNEL = "com.widdlereader.app/licensing"
    private val ANDROID_AUTO_CHANNEL = "com.widdlereader.app/android_auto"
    private val AUDIO_BRIDGE_CHANNEL = "com.widdlereader.app/audio_bridge"
    private val WIDGET_CHANNEL = "com.widdlereader.app/widget"
    private lateinit var preferences: SharedPreferences
    private var widgetChannel: MethodChannel? = null
    private var pendingScannerResult: MethodChannel.Result? = null
    
    companion object {
        private const val TAG = "MainActivity"
        private const val PREFS_FILE = "widdle_reader_license_prefs"
        private const val PREF_LICENSE_KEY = "license_key"
        private const val PREF_DEVICE_ID_KEY = "device_id_key"
        private const val PICK_FOLDER_REQUEST_CODE = 1001
        private const val PICK_FILE_CREATE_CODE = 1002
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_FOLDER_REQUEST_CODE) {
            if (resultCode == android.app.Activity.RESULT_OK && data != null) {
                val uri: Uri? = data.data
                if (uri != null) {
                    try {
                        contentResolver.takePersistableUriPermission(
                            uri,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                        )
                        pendingScannerResult?.success(uri.toString())
                    } catch (e: Exception) {
                        pendingScannerResult?.success(uri.toString())
                    }
                } else {
                    pendingScannerResult?.success(null)
                }
            } else {
                pendingScannerResult?.success(null)
            }
            pendingScannerResult = null
        } else if (requestCode == PICK_FILE_CREATE_CODE) {
            if (resultCode == android.app.Activity.RESULT_OK && data != null) {
                val uri: Uri? = data.data
                if (uri != null) {
                    try {
                        contentResolver.takePersistableUriPermission(
                            uri,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                        )
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to take persistable URI permission for created file: ${e.message}")
                    }
                    pendingScannerResult?.success(uri.toString())
                } else {
                    pendingScannerResult?.success(null)
                }
            } else {
                pendingScannerResult?.success(null)
            }
            pendingScannerResult = null
        }
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
        
        // Setup Widget channel for home screen widget actions
        setupWidgetChannel(flutterEngine)
    }
    
    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        
        // Handle widget button clicks
        when (intent.action) {
            "WIDGET_PLAY_PAUSE" -> {
                Log.d(TAG, "Widget: Play/Pause pressed")
                widgetChannel?.invokeMethod("playPause", null)
            }
            "WIDGET_SKIP_FORWARD" -> {
                Log.d(TAG, "Widget: Skip Forward pressed")
                widgetChannel?.invokeMethod("skipForward", null)
            }
            "WIDGET_SKIP_BACK" -> {
                Log.d(TAG, "Widget: Skip Back pressed")
                widgetChannel?.invokeMethod("skipBack", null)
            }
        }
    }
    
    private fun setupWidgetChannel(flutterEngine: FlutterEngine) {
        widgetChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL)
        widgetChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    Log.d(TAG, "Widget channel initialized")
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
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
                "pickFolder" -> {
                    pendingScannerResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                    startActivityForResult(intent, PICK_FOLDER_REQUEST_CODE)
                }
                "createFile" -> {
                    val fileName = call.argument<String>("fileName") ?: "widdle_reader_backup.json"
                    val mimeType = call.argument<String>("mimeType") ?: "application/json"
                    pendingScannerResult = result
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = mimeType
                        putExtra(Intent.EXTRA_TITLE, fileName)
                    }
                    startActivityForResult(intent, PICK_FILE_CREATE_CODE)
                }
                "getDisplayName" -> {
                    val path = call.argument<String>("path") ?: ""
                    if (path.isEmpty()) {
                        result.error("INVALID_PATH", "Path is empty", null)
                        return@setMethodCallHandler
                    }

                    try {
                        if (path.startsWith("content://")) {
                            val uri = Uri.parse(path)
                            val resolver = applicationContext.contentResolver
                            val docId = getDocId(uri)
                            
                            if (docId == null) {
                                result.success(null)
                                return@setMethodCallHandler
                            }

                            val docUri = if (path.contains("/tree/")) {
                                DocumentsContract.buildDocumentUriUsingTree(uri, docId)
                            } else {
                                DocumentsContract.buildDocumentUri(uri.authority, docId)
                            }

                            resolver.query(docUri, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { cursor ->
                                if (cursor.moveToFirst()) {
                                    val name = cursor.getString(0)
                                    if (!name.isNullOrEmpty()) {
                                        result.success(name)
                                        return@setMethodCallHandler
                                    }
                                }
                            }

                            // Fallback: Extract from docId if query fails or returns empty
                            val decodedId = Uri.decode(docId)
                            if (decodedId.contains("/")) {
                                result.success(decodedId.split("/").last())
                            } else if (decodedId.contains(":")) {
                                result.success(decodedId.split(":").last())
                            } else {
                                result.success(null)
                            }
                        } else {
                            val file = java.io.File(path)
                            result.success(file.name)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error getting display name: ${e.message}")
                        result.success(null)
                    }
                }
                "listDirectory" -> {
                    val path = call.argument<String>("path") ?: ""
                    if (path.isEmpty()) {
                        result.error("INVALID_PATH", "Path is empty", null)
                        return@setMethodCallHandler
                    }

                    try {
                        if (path.startsWith("content://")) {
                            val uri = Uri.parse(path)
                            val resolver = applicationContext.contentResolver
                            
                            // Robust ID extraction
                            val docId = getDocId(uri)
                            if (docId == null) {
                                Log.e(TAG, "listDirectory: Could not extract docId for: $path")
                                result.success(emptyList<Map<String, Any>>())
                                return@setMethodCallHandler
                            }

                            // Robust tree ID extraction for documents-under-tree
                            val childrenUri = if (path.contains("/tree/")) {
                                try {
                                    // Extract tree ID manually if it's a document URI
                                    val treeId = if (path.contains("/document/")) {
                                        val parts = path.split("/")
                                        val treeIdx = parts.indexOf("tree")
                                        if (treeIdx != -1 && treeIdx + 1 < parts.size) {
                                            Uri.decode(parts[treeIdx + 1])
                                        } else {
                                            DocumentsContract.getTreeDocumentId(uri)
                                        }
                                    } else {
                                        DocumentsContract.getTreeDocumentId(uri)
                                    }
                                    val baseTreeUri = DocumentsContract.buildTreeDocumentUri(uri.authority, treeId)
                                    DocumentsContract.buildChildDocumentsUriUsingTree(baseTreeUri, docId)
                                } catch (e: Exception) {
                                    Log.e(TAG, "Failed to build children URI using tree: ${e.message}")
                                    DocumentsContract.buildChildDocumentsUri(uri.authority, docId)
                                }
                            } else {
                                DocumentsContract.buildChildDocumentsUri(uri.authority, docId)
                            }

                            val resultList = mutableListOf<Map<String, Any>>()
                            
                            resolver.query(childrenUri, arrayOf(
                                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                                DocumentsContract.Document.COLUMN_MIME_TYPE,
                                DocumentsContract.Document.COLUMN_SIZE,
                                DocumentsContract.Document.COLUMN_LAST_MODIFIED
                            ), null, null, null)?.use { cursor ->
                                val idIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                                val nameIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                                val mimeIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
                                val sizeIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_SIZE)
                                val modIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_LAST_MODIFIED)

                                while (cursor.moveToNext()) {
                                    val childId = cursor.getString(idIdx)
                                    val name = cursor.getString(nameIdx) ?: "Unknown"
                                    val mimeType = cursor.getString(mimeIdx) ?: ""
                                    val size = cursor.getLong(sizeIdx)
                                    val lastModified = cursor.getLong(modIdx)
                                    
                                    val isDirectory = mimeType == DocumentsContract.Document.MIME_TYPE_DIR
                                    
                                    // Build a listable child URI with tree context if we have it
                                    val childUri = if (path.contains("/tree/")) {
                                        if (isDirectory) {
                                            // Keep tree URI for directories so they remain listable
                                            // Actually using buildDocumentUriUsingTree is correct for children
                                            DocumentsContract.buildDocumentUriUsingTree(uri, childId)
                                        } else {
                                            DocumentsContract.buildDocumentUriUsingTree(uri, childId)
                                        }
                                    } else {
                                        if (isDirectory) {
                                            DocumentsContract.buildTreeDocumentUri(uri.authority, childId)
                                        } else {
                                            DocumentsContract.buildDocumentUri(uri.authority, childId)
                                        }
                                    }

                                    resultList.add(mutableMapOf<String, Any>(
                                        "name" to name,
                                        "path" to childUri.toString(),
                                        "isDirectory" to isDirectory,
                                        "length" to size,
                                        "lastModified" to lastModified
                                    ))
                                }
                            }
                            Log.d(TAG, "listDirectory: Found ${resultList.size} items in $path")
                            result.success(resultList)
                        } else {
                            // ... (legacy File API remains the same)
                            val dir = java.io.File(path)
                            if (!dir.exists() || !dir.isDirectory) {
                                result.success(emptyList<Map<String, Any>>())
                                return@setMethodCallHandler
                            }

                            val files = dir.listFiles()
                            val resultList = mutableListOf<Map<String, Any>>()

                            files?.forEach { file ->
                                val map = mutableMapOf<String, Any>(
                                    "name" to file.name,
                                    "path" to file.absolutePath,
                                    "isDirectory" to file.isDirectory,
                                    "length" to file.length(),
                                    "lastModified" to file.lastModified()
                                )
                                resultList.add(map)
                            }
                            result.success(resultList)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error listing directory: ${e.message}")
                        result.error("LIST_ERROR", e.message, null)
                    }
                }
                "readBytes" -> {
                    val path = call.argument<String>("path") ?: ""
                    if (path.isEmpty()) {
                        result.error("INVALID_PATH", "Path is empty", null)
                        return@setMethodCallHandler
                    }

                    try {
                        if (path.startsWith("content://")) {
                            val uri = Uri.parse(path)
                            val resolver = applicationContext.contentResolver
                            resolver.openInputStream(uri)?.use { inputStream ->
                                result.success(inputStream.readBytes())
                            } ?: result.error("READ_ERROR", "Could not open input stream", null)
                        } else {
                            val file = java.io.File(path)
                            if (file.exists()) {
                                result.success(file.readBytes())
                            } else {
                                result.error("FILE_NOT_FOUND", "File does not exist: $path", null)
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error reading bytes: ${e.message}")
                        result.error("READ_ERROR", e.message, null)
                    }
                }
                "writeBytes" -> {
                    val path = call.argument<String>("path") ?: ""
                    val bytes = call.argument<ByteArray>("bytes")
                    val fileName = call.argument<String>("fileName")

                    if (path.isEmpty() || bytes == null) {
                        result.error("INVALID_ARGS", "Path or bytes empty", null)
                        return@setMethodCallHandler
                    }

                    try {
                        if (path.startsWith("content://")) {
                            val uri = Uri.parse(path)
                            val resolver = applicationContext.contentResolver
                            
                            // STRATEGY: First, try to write directly to the URI.
                            // This works for document URIs from ACTION_CREATE_DOCUMENT.
                            // If the URI is a directory tree, this will fail gracefully.
                            try {
                                Log.d(TAG, "writeBytes: Attempting direct write to $path (${bytes.size} bytes)")
                                resolver.openOutputStream(uri, "w")?.use { outputStream ->
                                    outputStream.write(bytes)
                                    outputStream.flush()
                                }
                                Log.d(TAG, "writeBytes: Direct write succeeded to $path")
                                result.success(uri.toString())
                                return@setMethodCallHandler
                            } catch (directWriteError: Exception) {
                                Log.d(TAG, "writeBytes: Direct write failed (${directWriteError.message}), trying directory logic...")
                            }
                            
                            // FALLBACK: If direct write fails, treat path as a directory and create a file within it.
                            if (fileName == null) {
                                result.error("WRITE_ERROR", "Direct write failed and no fileName provided for directory write.", null)
                                return@setMethodCallHandler
                            }
                            
                            val dirDoc = DocumentFile.fromTreeUri(applicationContext, uri)
                            if (dirDoc != null && dirDoc.exists() && dirDoc.isDirectory) {
                                val mimeType = when {
                                    fileName.endsWith(".json", ignoreCase = true) -> "application/json"
                                    fileName.endsWith(".jpg", ignoreCase = true) || fileName.endsWith(".jpeg", ignoreCase = true) -> "image/jpeg"
                                    fileName.endsWith(".png", ignoreCase = true) -> "image/png"
                                    else -> "application/octet-stream"
                                }
                                
                                var fileDoc = dirDoc.findFile(fileName)
                                if (fileDoc == null) {
                                    fileDoc = dirDoc.createFile(mimeType, fileName)
                                }
                                
                                if (fileDoc != null) {
                                    resolver.openOutputStream(fileDoc.uri, "w")?.use { outputStream ->
                                        outputStream.write(bytes)
                                        outputStream.flush()
                                    }
                                    Log.d(TAG, "writeBytes: Directory write succeeded to ${fileDoc.uri}")
                                    result.success(fileDoc.uri.toString())
                                } else {
                                    result.error("CREATE_ERROR", "Could not create file '$fileName' in directory", null)
                                }
                            } else {
                                result.error("WRITE_ERROR", "Path is not a writable file or directory: $path", null)
                            }
                        } else {
                            // Legacy File API for non-content:// paths
                            val targetFile = if (fileName != null) {
                                java.io.File(path, fileName)
                            } else {
                                java.io.File(path)
                            }
                            targetFile.parentFile?.mkdirs()
                            targetFile.writeBytes(bytes)
                            result.success(targetFile.absolutePath)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error writing bytes: ${e.message}", e)
                        result.error("WRITE_ERROR", e.message, null)
                    }
                }
                "getMetadata" -> {
                    val path = call.argument<String>("path") ?: ""
                    if (path.isEmpty()) {
                        result.error("INVALID_PATH", "Path is empty", null)
                        return@setMethodCallHandler
                    }

                    val retriever = MediaMetadataRetriever()
                    try {
                        // Check file size first - skip cover extraction for large files (>200MB)
                        // to prevent OOM/hanging on large audiobooks
                        var fileSize: Long = 0
                        try {
                            if (path.startsWith("content://")) {
                                val uri = Uri.parse(path)
                                applicationContext.contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
                                    fileSize = pfd.statSize
                                }
                            } else {
                                fileSize = java.io.File(path).length()
                            }
                        } catch (e: Exception) {
                            Log.w(TAG, "Could not determine file size for $path: ${e.message}")
                        }
                        
                        val maxSizeForCover = 200 * 1024 * 1024L // 200MB
                        val shouldExtractCover = call.argument<Boolean>("extractCover") == true && fileSize < maxSizeForCover
                        
                        if (fileSize >= maxSizeForCover) {
                            Log.d(TAG, "Large file detected (${fileSize / 1024 / 1024}MB), skipping native cover extraction")
                        }

                        if (path.startsWith("content://")) {
                            val uri = Uri.parse(path)
                            retriever.setDataSource(applicationContext, uri)
                        } else {
                            retriever.setDataSource(path)
                        }

                        val metadata = mutableMapOf<String, Any?>()
                        metadata["title"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)
                        metadata["artist"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST) ?: retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST)
                        metadata["album"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)
                        metadata["duration"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
                        metadata["fileSize"] = fileSize
                        
                        if (shouldExtractCover) {
                            metadata["coverArt"] = retriever.embeddedPicture
                        }

                        result.success(metadata)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error extracting metadata: ${e.message}")
                        result.error("METADATA_ERROR", e.message, null)
                    } finally {
                        try {
                            retriever.release()
                        } catch (e: Exception) { }
                    }
                }
                "recursiveScan" -> {
                    val path = call.argument<String>("path") ?: ""
                    Log.d(TAG, "Native recursiveScan starting for: $path")
                    if (path.isEmpty()) {
                        result.error("INVALID_PATH", "Path is empty", null)
                        return@setMethodCallHandler
                    }

                    Thread {
                        try {
                            val audioFolders = mutableListOf<String>()
                            if (path.startsWith("content://")) {
                                val rootUri = Uri.parse(path)
                                val rootDocId = DocumentsContract.getTreeDocumentId(rootUri)
                                Log.d(TAG, "Starting SAF recursion with raw resolver. Tree: $rootUri, RootID: $rootDocId")
                                scanSAFRecursive(rootUri, rootDocId, audioFolders)
                            } else {
                                val rootDir = java.io.File(path)
                                if (rootDir.exists() && rootDir.isDirectory) {
                                    Log.d(TAG, "Root directory exists. Starting File recursion...")
                                    scanFileRecursive(rootDir, audioFolders)
                                } else {
                                    Log.e(TAG, "Root directory does NOT exist for path: $path")
                                }
                            }
                            Log.d(TAG, "Scan finished. Found ${audioFolders.size} folders.")
                            Handler(Looper.getMainLooper()).post {
                                result.success(audioFolders.distinct())
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error in recursive scan: ${e.message}")
                            Handler(Looper.getMainLooper()).post {
                                result.error("SCAN_ERROR", e.message, null)
                            }
                        }
                    }.start()
                }
                "createNomediaFile" -> {
                    val path = call.argument<String>("path") ?: ""
                    if (path.isEmpty()) {
                        result.error("INVALID_PATH", "Path is empty", null)
                        return@setMethodCallHandler
                    }

                    try {
                        if (path.startsWith("content://")) {
                            val uri = Uri.parse(path)
                            val dirDoc = if (path.contains("/document/")) {
                                DocumentFile.fromSingleUri(applicationContext, uri)
                            } else {
                                DocumentFile.fromTreeUri(applicationContext, uri)
                            }

                            if (dirDoc != null && dirDoc.exists() && dirDoc.isDirectory) {
                                val nomedia = dirDoc.findFile(".nomedia")
                                if (nomedia == null) {
                                    dirDoc.createFile("application/octet-stream", ".nomedia")
                                }
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        } else {
                            val nomedia = java.io.File(path, ".nomedia")
                            if (!nomedia.exists()) {
                                nomedia.createNewFile()
                            }
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("NOMEDIA_ERROR", e.message, null)
                    }
                }
                "hasNomediaFile" -> {
                    val path = call.argument<String>("path") ?: ""
                    if (path.isEmpty()) {
                        result.error("INVALID_PATH", "Path is empty", null)
                        return@setMethodCallHandler
                    }

                    try {
                        if (path.startsWith("content://")) {
                            val uri = Uri.parse(path)
                            val dirDoc = if (path.contains("/document/")) {
                                DocumentFile.fromSingleUri(applicationContext, uri)
                            } else {
                                DocumentFile.fromTreeUri(applicationContext, uri)
                            }
                            val nomedia = dirDoc?.findFile(".nomedia")
                            result.success(nomedia != null && nomedia.exists())
                        } else {
                            val nomedia = java.io.File(path, ".nomedia")
                            result.success(nomedia.exists())
                        }
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "exists" -> {
                    val path = call.argument<String>("path") ?: ""
                    if (path.isEmpty()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        if (path.startsWith("content://")) {
                            val uri = Uri.parse(path)
                            val doc = if (path.contains("/document/")) {
                                DocumentFile.fromSingleUri(applicationContext, uri)
                            } else {
                                DocumentFile.fromTreeUri(applicationContext, uri)
                            }
                            result.success(doc?.exists() ?: false)
                        } else {
                            result.success(java.io.File(path).exists())
                        }
                    } catch (e: Exception) {
                        result.success(false)
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
                            // CRITICAL FIX #4: Enhanced parcel unmarshalling with validation
                            if (tokenBytes.isEmpty()) {
                                Log.e(TAG, "ERROR: Token bytes array is empty")
                                result.error("INVALID_TOKEN", "Token bytes array is empty", null)
                                return@setMethodCallHandler
                            }
                            
                            val parcel = Parcel.obtain()
                            try {
                                parcel.unmarshall(tokenBytes, 0, tokenBytes.size)
                                parcel.setDataPosition(0)
                                
                                // Validate parcel has data
                                if (parcel.dataSize() == 0) {
                                    Log.e(TAG, "ERROR: Parcel has no data after unmarshalling")
                                    result.error("INVALID_TOKEN", "Token unmarshalling produced empty parcel", null)
                                    return@setMethodCallHandler
                                }
                                
                                val token = MediaSessionCompat.Token.CREATOR.createFromParcel(parcel)
                                bridge.registerSessionToken(token)
                                result.success(mapOf(
                                    "success" to true,
                                    "hasDirectControl" to bridge.hasDirectControl()
                                ))
                            } catch (e: RuntimeException) {
                                Log.e(TAG, "ERROR: Runtime exception during parcel creation: ${e.message}", e)
                                result.error("PARCEL_ERROR", "Failed to create token from parcel: ${e.message}", null)
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
                        val mediaId = call.argument<String>("mediaId")
                        val title = call.argument<String>("title")
                        val artUri = call.argument<String>("artUri")
                        Log.d(TAG, "updateMetadata: mediaId=$mediaId, title=$title, artUri=$artUri")
                        
                        bridge.updateMetadata(
                            mediaId = mediaId,
                            title = title ?: "Unknown",
                            artist = call.argument<String>("artist") ?: "Unknown Artist",
                            album = call.argument<String>("album") ?: "",
                            duration = call.argument<Number>("duration")?.toLong() ?: 0L,
                            artUri = artUri,
                            displayTitle = call.argument<String>("displayTitle"),
                            displaySubtitle = call.argument<String>("displaySubtitle"),
                            displayDescription = call.argument<String>("displayDescription"),
                            chapterTitle = call.argument<String>("chapterTitle")
                        )
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
                "clearMediaSession" -> {
                    try {
                        // Update playback state to stopped/none
                        bridge.updatePlaybackState(
                            position = 0L,
                            isPlaying = false,
                            speed = 1.0f,
                            hasNext = false,
                            hasPrevious = false
                        )
                        Log.d(TAG, "MediaSession cleared for backup restore")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error clearing MediaSession: ${e.message}")
                        result.error("CLEAR_ERROR", e.message, null)
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
    
    private fun scanSAFRecursive(rootTreeUri: Uri, currentDocId: String, resultList: MutableList<String>) {
        val resolver = applicationContext.contentResolver
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(rootTreeUri, currentDocId)
        
        val subDirs = mutableListOf<String>()
        var hasAudioInThisDir = false
        var dirName = "Unknown"

        // Get directory name and verify it's a directory
        val docUri = DocumentsContract.buildDocumentUriUsingTree(rootTreeUri, currentDocId)
        resolver.query(docUri, arrayOf(
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE
        ), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                dirName = cursor.getString(0) ?: "Unknown"
                val mime = cursor.getString(1) ?: ""
                if (mime != DocumentsContract.Document.MIME_TYPE_DIR) return
            }
        }

        Log.d(TAG, "Entering directory: $dirName (ID: $currentDocId)")

        resolver.query(childrenUri, arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE
        ), null, null, null)?.use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)

            while (cursor.moveToNext()) {
                val childId = cursor.getString(idIdx)
                val childName = cursor.getString(nameIdx) ?: ""
                val childMime = cursor.getString(mimeIdx) ?: ""
                
                if (childMime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    subDirs.add(childId)
                } else if (isAudioFile(childName, childMime)) {
                    Log.d(TAG, "    [AUDIO] $childName (Type: $childMime)")
                    hasAudioInThisDir = true
                }
            }
        }

        if (hasAudioInThisDir) {
            Log.d(TAG, "  [FOLDER ADDED] $dirName")
            // Return the document-under-tree URI for the folder
            resultList.add(docUri.toString())
        }

        for (childId in subDirs) {
            scanSAFRecursive(rootTreeUri, childId, resultList)
        }
    }

    private fun scanFileRecursive(dir: java.io.File, resultList: MutableList<String>) {
        val files = dir.listFiles() ?: return
        var hasAudioInThisDir = false
        val subDirs = mutableListOf<java.io.File>()

        for (file in files) {
            if (file.isDirectory) {
                subDirs.add(file)
            } else if (file.isFile) {
                val name = file.name
                if (isAudioFile(name, null)) {
                    hasAudioInThisDir = true
                }
            }
        }

        if (hasAudioInThisDir) {
            resultList.add(dir.absolutePath)
        }

        for (subDir in subDirs) {
            scanFileRecursive(subDir, resultList)
        }
    }

    private fun getDocId(uri: Uri): String? {
        return try {
            if (DocumentsContract.isDocumentUri(applicationContext, uri)) {
                DocumentsContract.getDocumentId(uri)
            } else {
                DocumentsContract.getTreeDocumentId(uri)
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun isAudioFile(name: String, type: String?): Boolean {
        val lowerName = name.toLowerCase()
        // Broad extension check
        val audioExts = listOf(".mp3", ".m4a", ".m4b", ".wav", ".ogg", ".aac", ".flac", ".opus", ".mp4", ".m4p", ".wma")
        if (audioExts.any { lowerName.endsWith(it) }) return true
        
        // Broad MIME type check (SAF)
        if (type != null) {
            if (type.startsWith("audio/")) return true
            if (type.startsWith("video/")) {
                // Many audio-only files are reported as video/mp4 by some providers
                val videoAudioExts = listOf(".mp4", ".m4a", ".m4b", ".m4v")
                if (videoAudioExts.any { lowerName.endsWith(it) }) return true
            }
            if (type == "application/ogg" || type == "application/x-flac" || type == "application/octet-stream") {
                // octet-stream is a fallback for unknown types, check extension
                if (audioExts.any { lowerName.endsWith(it) }) return true
            }
        }
        
        return false
    }

    private fun sha256(input: String): String {
        val bytes = input.toByteArray()
        val md = MessageDigest.getInstance("SHA-256")
        val digest = md.digest(bytes)
        return digest.fold("") { str, it -> str + "%02x".format(it) }
    }
}
