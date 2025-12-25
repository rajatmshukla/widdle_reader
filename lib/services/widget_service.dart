import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'simple_audio_service.dart';

/// Service to sync audiobook playback state to the home screen widget
class WidgetService {
  // Singleton instance
  static final WidgetService _instance = WidgetService._internal();
  factory WidgetService() => _instance;
  WidgetService._internal();

  static const _widgetChannel = MethodChannel('com.widdlereader.app/widget');
  bool _initialized = false;

  /// Initialize the widget service and set up method channel handlers
  Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      // Set the app group ID (required for iOS, optional for Android)
      await HomeWidget.setAppGroupId('group.com.widdlereader.app');
      
      // Set up method channel handler for widget button clicks
      _widgetChannel.setMethodCallHandler(_handleWidgetMethod);
      
      _initialized = true;
      debugPrint('📱 WidgetService initialized');
    } catch (e) {
      debugPrint('📱 WidgetService init error: $e');
    }
  }

  /// Handle method calls from native widget
  Future<dynamic> _handleWidgetMethod(MethodCall call) async {
    final audioService = SimpleAudioService();
    
    switch (call.method) {
      case 'playPause':
        debugPrint('📱 Widget: Play/Pause action received');
        if (audioService.isPlaying) {
          await audioService.pause();
        } else {
          await audioService.play();
        }
        break;
      case 'skipForward':
        debugPrint('📱 Widget: Skip Forward action received');
        await audioService.fastForward();
        break;
      case 'skipBack':
        debugPrint('📱 Widget: Skip Back action received');
        await audioService.rewind();
        break;
      default:
        debugPrint('📱 Widget: Unknown action ${call.method}');
    }
    return null;
  }

  /// Update the widget with current playback state
  Future<void> updateWidget({
    required String bookTitle,
    required String chapterTitle,
    required bool isPlaying,
    String? coverPath,
  }) async {
    try {
      // Save data to SharedPreferences (accessed by native widget)
      await HomeWidget.saveWidgetData<String>('book_title', bookTitle);
      await HomeWidget.saveWidgetData<String>('chapter_title', chapterTitle);
      await HomeWidget.saveWidgetData<bool>('is_playing', isPlaying);
      
      if (coverPath != null) {
        await HomeWidget.saveWidgetData<String>('cover_path', coverPath);
      }

      // Request widget update
      await HomeWidget.updateWidget(
        name: 'AudiobookWidgetProvider',
        androidName: 'AudiobookWidgetProvider',
        qualifiedAndroidName: 'com.widdlereader.app.AudiobookWidgetProvider',
      );

      debugPrint('📱 Widget updated: $bookTitle | $chapterTitle | playing=$isPlaying | cover=$coverPath');
    } catch (e) {
      debugPrint('📱 Widget update error: $e');
    }
  }

  /// Clear widget data (no book playing)
  Future<void> clearWidget() async {
    try {
      await HomeWidget.saveWidgetData<String>('book_title', 'No book selected');
      await HomeWidget.saveWidgetData<String>('chapter_title', 'Tap to open app');
      await HomeWidget.saveWidgetData<bool>('is_playing', false);

      await HomeWidget.updateWidget(
        name: 'AudiobookWidgetProvider',
        androidName: 'AudiobookWidgetProvider',
        qualifiedAndroidName: 'com.widdlereader.app.AudiobookWidgetProvider',
      );

      debugPrint('📱 Widget cleared');
    } catch (e) {
      debugPrint('📱 Widget clear error: $e');
    }
  }
}
