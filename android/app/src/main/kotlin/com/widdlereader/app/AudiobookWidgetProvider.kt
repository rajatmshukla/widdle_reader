package com.widdlereader.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import android.widget.RemoteViews
import java.io.File
import android.util.Log
import com.widdlereader.app.auto.WiddleReaderMediaService

/**
 * Audiobook Widget Provider - Resizable home screen widget
 * Displays current audiobook, chapter, and playback controls
 */
class AudiobookWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val PREFS_NAME = "HomeWidgetPreferences"
        // Actions handled by WiddleReaderMediaService
        private const val ACTION_PLAY = "com.widdlereader.app.ACTION_PLAY"
        private const val ACTION_PAUSE = "com.widdlereader.app.ACTION_PAUSE"
        private const val ACTION_SKIP_FORWARD = "com.widdlereader.app.ACTION_SKIP_FORWARD"
        private const val ACTION_SKIP_BACK = "com.widdlereader.app.ACTION_SKIP_BACK"
        
        // Actions handled locally or via MainActivity
        private const val ACTION_OPEN_APP = "com.widdlereader.app.ACTION_OPEN_APP"

        // Size thresholds (in dp)
        private const val SMALL_WIDTH = 150
        private const val MEDIUM_WIDTH = 220
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle?
    ) {
        // Called when widget is resized
        updateAppWidget(context, appWidgetManager, appWidgetId)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        Log.d("WidgetProvider", "Received action: ${intent.action}")

        when (intent.action) {
            ACTION_OPEN_APP -> {
                val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
                launchIntent?.let { context.startActivity(it) }
            }
        }
    }

    private fun updateAppWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        // Get widget size to determine layout
        val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
        val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)

        // Select layout based on size
        val layoutId = when {
            minWidth < SMALL_WIDTH -> R.layout.widget_audiobook_small
            minWidth < MEDIUM_WIDTH -> R.layout.widget_audiobook
            else -> R.layout.widget_audiobook_large
        }

        val views = RemoteViews(context.packageName, layoutId)

        // Get data from SharedPreferences (set by Flutter via home_widget)
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val bookTitle = prefs.getString("book_title", "No book selected") ?: "No book selected"
        val chapterTitle = prefs.getString("chapter_title", "Tap to open app") ?: "Tap to open app"
        val isPlaying = prefs.getBoolean("is_playing", false)
        val coverPath = prefs.getString("cover_path", null)

        // Set text views
        views.setTextViewText(R.id.widget_book_title, bookTitle)
        
        // Chapter title only exists in medium and large layouts
        if (layoutId != R.layout.widget_audiobook_small) {
            views.setTextViewText(R.id.widget_chapter_title, chapterTitle)
        }

        // Set play/pause icon
        val playPauseIcon = if (isPlaying) {
            android.R.drawable.ic_media_pause
        } else {
            android.R.drawable.ic_media_play
        }
        views.setImageViewResource(R.id.widget_play_pause, playPauseIcon)

        // Set Cover Art if available and layout has image view
        if (layoutId == R.layout.widget_audiobook_large) {
             if (coverPath != null && File(coverPath).exists()) {
                 try {
                     val options = BitmapFactory.Options().apply {
                         inJustDecodeBounds = true
                     }
                     BitmapFactory.decodeFile(coverPath, options)
                     options.inSampleSize = calculateInSampleSize(options, 120, 120)
                     options.inJustDecodeBounds = false
                     
                     val bitmap = BitmapFactory.decodeFile(coverPath, options)
                     views.setImageViewBitmap(R.id.widget_app_icon, bitmap)
                 } catch (e: Exception) {
                     Log.e("WidgetProvider", "Error loading cover art: $e")
                     views.setImageViewResource(R.id.widget_app_icon, R.mipmap.ic_launcher)
                 }
             } else {
                 views.setImageViewResource(R.id.widget_app_icon, R.mipmap.ic_launcher)
             }
        }

        // Set up PendingIntents using getService to avoid opening app
        // Play/Pause - determines action based on current state
        val playPauseAction = if (isPlaying) ACTION_PAUSE else ACTION_PLAY
        val playPauseIntent = Intent(context, WiddleReaderMediaService::class.java).apply {
            action = playPauseAction
        }
        val playPausePending = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(
                context, 0, playPauseIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else {
            PendingIntent.getService(
                context, 0, playPauseIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
        views.setOnClickPendingIntent(R.id.widget_play_pause, playPausePending)

        // Skip buttons (only in large layout)
        if (layoutId == R.layout.widget_audiobook_large) {
            val skipForwardIntent = Intent(context, WiddleReaderMediaService::class.java).apply {
                action = ACTION_SKIP_FORWARD
            }
            val skipForwardPending = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                PendingIntent.getForegroundService(
                    context, 1, skipForwardIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            } else {
                PendingIntent.getService(
                    context, 1, skipForwardIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            }
            views.setOnClickPendingIntent(R.id.widget_skip_forward, skipForwardPending)

            val skipBackIntent = Intent(context, WiddleReaderMediaService::class.java).apply {
                action = ACTION_SKIP_BACK
            }
            val skipBackPending = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                PendingIntent.getForegroundService(
                    context, 2, skipBackIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            } else {
                PendingIntent.getService(
                    context, 2, skipBackIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            }
            views.setOnClickPendingIntent(R.id.widget_skip_back, skipBackPending)
        }

        // Open app when tapping on the widget body
        val openAppIntent = Intent(context, AudiobookWidgetProvider::class.java).apply {
            action = ACTION_OPEN_APP
        }
        val openAppPending = PendingIntent.getBroadcast(
            context, 3, openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_container, openAppPending)

        // Update the widget
        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun calculateInSampleSize(options: BitmapFactory.Options, reqWidth: Int, reqHeight: Int): Int {
        val (height: Int, width: Int) = options.run { outHeight to outWidth }
        var inSampleSize = 1

        if (height > reqHeight || width > reqWidth) {
            val halfHeight: Int = height / 2
            val halfWidth: Int = width / 2

            while ((halfHeight / inSampleSize) >= reqHeight && (halfWidth / inSampleSize) >= reqWidth) {
                inSampleSize *= 2
            }
        }
        return inSampleSize
    }
}
