import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

import '../models/audiobook.dart';
import '../providers/audiobook_provider.dart';
import '../services/simple_audio_service.dart';
import '../services/storage_service.dart';

/// Android Auto Manager
/// 
/// Manages integration between Flutter app and Android Auto MediaBrowserService
/// Provides:
/// - Data synchronization via SharedPreferences
/// - Playback command handling
/// - Real-time state updates
/// - Material 3-inspired content organization
class AndroidAutoManager {
  static const String _logPrefix = 'AndroidAuto';
  static const String _prefsPrefix = 'android_auto_';
  
  // Singleton pattern
  static final AndroidAutoManager _instance = AndroidAutoManager._internal();
  factory AndroidAutoManager() => _instance;
  AndroidAutoManager._internal();
  
  // Method channel for native communication
  static const _audioBridgeChannel = MethodChannel('com.widdlereader.app/audio_bridge');
  
  // State
  bool _initialized = false;
  bool _isAndroidAuto = false;
  Timer? _syncTimer;
  Timer? _commandListenerTimer;
  
  // Services
  SharedPreferences? _prefs;
  AudiobookProvider? _audiobookProvider;
  SimpleAudioService? _audioService;
  StorageService? _storageService;
  
  /// Initialize Android Auto integration
  Future<void> initialize({
    required AudiobookProvider audiobookProvider,
    required SimpleAudioService audioService,
    required StorageService storageService,
  }) async {
    if (_initialized) {
      _logDebug('Already initialized');
      return;
    }
    
    // Only initialize on Android
    if (!Platform.isAndroid) {
      _logDebug('Not Android platform, skipping initialization');
      return;
    }
    
    _logDebug('Initializing Android Auto integration');
    
    _audiobookProvider = audiobookProvider;
    _audioService = audioService;
    _storageService = storageService;
    
    try {
      // Get SharedPreferences instance
      _prefs = await SharedPreferences.getInstance();
      _setupAudioBridgeHandler();
      
      // Initial data sync
      await syncDataToNative();
      
      // Start periodic sync (every 5 seconds to keep Android Auto updated)
      _startPeriodicSync();
      
      // Check for any pending commands immediately (e.g. if app was launched by Android Auto)
      await _checkForPlaybackCommands();
      
      // Start listening for playback commands from Android Auto
      _startCommandListener();
      
      _initialized = true;
      _isAndroidAuto = true;
      
      _logDebug('Android Auto integration initialized successfully');
    } catch (e) {
      _logDebug('Error initializing Android Auto: $e');
    }
  }
  
  /// Dispose and cleanup
  void dispose() {
    _syncTimer?.cancel();
    _commandListenerTimer?.cancel();
    _initialized = false;
    _logDebug('Android Auto manager disposed');
  }
  
  /// Check if Android Auto is available and active
  bool get isAndroidAutoActive => _isAndroidAuto && _initialized;
  
  /// Sync all data from Flutter to native side
  Future<void> syncDataToNative() async {
    if (_prefs == null || _audiobookProvider == null) return;
    
    try {
      // Sync audiobooks
      await _syncAudiobooks();
      
      // Sync playback state
      await _syncPlaybackState();
      
      // Sync tags
      await _syncTags();
      
      // Force MediaSession sync via MethodChannel
      if (_audioService != null) {
        await _audioService!.forceSyncStateToNative();
      }
      
      _logDebug('Data synced to native successfully');
    } catch (e) {
      _logDebug('Error syncing data: $e');
    }
  }
  
  /// Sync audiobooks to native
  Future<void> _syncAudiobooks() async {
    if (_prefs == null || _audiobookProvider == null) return;
    
    final audiobooks = _audiobookProvider!.audiobooks;
    _logDebug('🔄 SYNC: Starting audiobook sync - count: ${audiobooks.length}');
    final audiobooksData = <Map<String, dynamic>>[];
    
    for (final book in audiobooks) {
      // Get additional data from storage
      final progress = await _storageService?.loadProgressCache(book.id) ?? 0.0;
      final lastPlayed = await _storageService?.getLastPlayedTimestamp(book.id) ?? 0;
      final isCompleted = await _storageService?.isCompleted(book.id) ?? false;
      
      _logDebug('📖 Book: ${book.title} | lastPlayed: $lastPlayed | progress: ${(progress * 100).toStringAsFixed(1)}%');
      
      // Prepare audiobook data
      final bookData = <String, dynamic>{
        'id': book.id,
        'title': _audiobookProvider!.getTitleForAudiobook(book),
        'author': book.author ?? 'Unknown Author',
        'chapterCount': book.chapters.length,
        'totalDuration': book.totalDuration.inMilliseconds,
        'progress': progress,
        'lastPlayed': lastPlayed,
        'isCompleted': isCompleted,
        'isFavorited': book.isFavorited,
        'tags': book.tags.toList(),
        'chapters': book.chapters.map((chapter) => {
          'id': chapter.id,
          'title': chapter.title,
          'duration': chapter.duration?.inMilliseconds ?? 0,
        }).toList(),
      };
      
      // Add cover art path if available (avoid base64 to prevent OOM)
      String? coverPath = await _storageService?.getCoverArtUri(book.id);
      
      // Fallback: If persistent cache is missing but we have bytes in memory, 
      // write to a temporary file so Native can read it.
      if (coverPath == null && book.coverArt != null) {
        try {
          final tempDir = await getTemporaryDirectory();
          final start = DateTime.now().millisecondsSinceEpoch;
          // Use sanitized ID for filename
          final sanitizedId = book.id.hashCode.toString();
          final file = File('${tempDir.path}/aa_cover_$sanitizedId.jpg');
          
          if (!await file.exists()) {
             await file.writeAsBytes(book.coverArt!);
             debugPrint("wrote temp cover for AA: ${file.path} (${book.coverArt!.length} bytes)");
          }
          coverPath = file.path;
        } catch (e) {
          debugPrint("Error creating temp cover art for AA: $e");
        }
      }

      if (coverPath != null) {
        bookData['coverArt'] = coverPath;
      } else if (book.coverArt != null) {
        // Only if file writing failed, maybe try base64 but for small images only?
        // Risky. Let's just log warning.
        debugPrint("Warning: Could not provide file path for cover art: ${book.title}");
      }
      
      audiobooksData.add(bookData);
    }
    
    // Save to SharedPreferences
    final key = '${_prefsPrefix}audiobooks';
    final jsonData = jsonEncode(audiobooksData);
    await _prefs!.setString(key, jsonData);
    
    _logDebug('✅ SYNC: Saved ${audiobooksData.length} audiobooks to key: $key');
    _logDebug('📝 SYNC: First 300 chars: ${jsonData.length > 300 ? jsonData.substring(0, 300) : jsonData}...');
  }
  
  /// Sync playback state to native
  Future<void> _syncPlaybackState() async {
    if (_prefs == null || _audioService == null) return;
    
    final state = <String, dynamic>{
      'isPlaying': _audioService!.isPlaying,
      'position': _audioService!.position.inMilliseconds,
      'duration': _audioService!.duration?.inMilliseconds ?? 0,
      'speed': _audioService!.speed,
      'chapterIndex': _audioService!.currentChapterIndex,
    };
    
    // Add current audiobook info
    final currentBook = _audioService!.currentAudiobook;
    if (currentBook != null) {
      state['audiobookId'] = currentBook.id;
      state['audiobookTitle'] = _audiobookProvider?.getTitleForAudiobook(currentBook) ?? currentBook.title;
      state['audiobookAuthor'] = currentBook.author ?? 'Unknown Author';
      
      // Current chapter info
      if (_audioService!.currentChapterIndex < currentBook.chapters.length) {
        final chapter = currentBook.chapters[_audioService!.currentChapterIndex];
        state['chapterId'] = chapter.id;
        state['chapterTitle'] = chapter.title;
      }
    }
    
    await _prefs!.setString(
      '${_prefsPrefix}playback_state',
      jsonEncode(state),
    );
  }
  
  /// Sync tags to native
  Future<void> _syncTags() async {
    if (_prefs == null) return;
    
    try {
      // This would need to be passed in or accessed via a provider
      // For now, create a simple structure
      final tags = <Map<String, dynamic>>[];
      
      // Note: You'll need to pass TagProvider instance to access tags
      // This is a placeholder structure
      
      await _prefs!.setString(
        '${_prefsPrefix}tags',
        jsonEncode(tags),
      );
      
      // Sync audiobook-tag assignments
      final audiobookTags = <String, List<String>>{};
      
      if (_audiobookProvider != null) {
        for (final book in _audiobookProvider!.audiobooks) {
          if (book.tags.isNotEmpty) {
            audiobookTags[book.id] = book.tags.toList();
          }
        }
      }
      
      await _prefs!.setString(
        '${_prefsPrefix}audiobook_tags',
        jsonEncode(audiobookTags),
      );
      
    } catch (e) {
      _logDebug('Error syncing tags: $e');
    }
  }
  
  /// Start periodic data sync
  void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      syncDataToNative();
    });
  }
  
  /// Start listening for playback commands from Android Auto
  /// Note: With AudioSessionBridge, this is now a fallback mechanism
  /// Direct MediaSession control happens with zero latency
  void _startCommandListener() {
    _commandListenerTimer?.cancel();
    _logDebug('🎧 Starting command listener (polling every 2 seconds)');
    
    // Check for direct control, only poll if using fallback
    _commandListenerTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      // Check if native side has direct control
      try {
        final hasDirectControl = await _audioBridgeChannel.invokeMethod<bool>('hasDirectControl') ?? false;
        if (!hasDirectControl) {
          // Only check commands if using fallback mode
          _checkForPlaybackCommands();
        } else {
          // Log only occasionally to avoid spam
          if (DateTime.now().second % 10 == 0) {
            _logDebug('ℹ️ Using direct MediaSession control, no polling needed');
          }
        }
      } catch (e) {
        // If method channel fails, fall back to checking commands
        _checkForPlaybackCommands();
      }
    });
    
    _logDebug('✅ Command listener started successfully');
  }

  void _setupAudioBridgeHandler() {
    _audioBridgeChannel.setMethodCallHandler((call) async {
      if (call.method != 'mediaSessionCommand') {
        return null;
      }

      final rawArgs = call.arguments;
      if (rawArgs is! Map) {
        _logDebug('⚠️ CMD_HANDLER: Invalid arguments: $rawArgs');
        throw PlatformException(code: 'INVALID_ARGS', message: 'Expected map arguments');
      }

      final args = rawArgs.cast<String, dynamic>();
      final action = args['action'] as String?;
      final params = (args['params'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

      if (action == null || action.isEmpty) {
        _logDebug('⚠️ CMD_HANDLER: Missing action in command');
        throw PlatformException(code: 'INVALID_ACTION', message: 'Missing command action');
      }

      _logDebug('🎯 CMD_HANDLER: Handling direct command → $action');
      if (_audioService == null) {
        throw PlatformException(
          code: 'NO_AUDIO_SERVICE',
          message: 'Audio service not ready for command $action',
        );
      }
      await _handlePlaybackCommand(action, params);
      return true;
    });
  }
  
  /// Check for and handle playback commands from Android Auto
  Future<void> _checkForPlaybackCommands() async {
    if (_prefs == null || _audioService == null) {
      _logDebug('⚠️ CMD_CHECK: Skipped - prefs or audioService is null');
      return;
    }

    final key = '${_prefsPrefix}playback_command';
    _logDebug('🔍 CMD_CHECK: Reading from key: $key');

    String? commandJson = _prefs!.getString(key);
    if (commandJson == null) {
      _logDebug('❌ CMD_CHECK: No command found — reloading prefs');
      try {
        await _prefs!.reload();
        commandJson = _prefs!.getString(key);
      } catch (e) {
        _logDebug('⚠️ CMD_CHECK: Reload failed: $e');
      }
    }

    if (commandJson == null) {
      final legacyKey = 'flutter.$key';
      final legacyValue = _prefs!.getString(legacyKey);
      if (legacyValue != null) {
        _logDebug('♻️ CMD_CHECK: Migrating legacy command from $legacyKey');
        await _prefs!.setString(key, legacyValue);
        await _prefs!.remove(legacyKey);
        commandJson = legacyValue;
      }
    }

    if (commandJson == null) {
      _logDebug('❌ CMD_CHECK: Command still not found. Keys: ${_prefs!.getKeys().where((k) => k.contains('android_auto')).toList()}');
      return;
    }

    _logDebug('🎯 CMD_FOUND raw: $commandJson');

    bool handled = false;

    try {
      final trimmed = commandJson.trim();
      Map<String, dynamic> command;

      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        command = jsonDecode(trimmed) as Map<String, dynamic>;
      } else {
        _logDebug('⚠️ CMD_CHECK: Command stored as raw string, wrapping');
        command = {
          'action': trimmed,
          'params': <String, dynamic>{},
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
      }

      final action = (command['action'] as String?)?.trim();
      final params = (command['params'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final timestamp = command['timestamp'] as int?;

      if (timestamp != null &&
          DateTime.now().millisecondsSinceEpoch - timestamp > 2000) {
        _logDebug('⌛ CMD_CHECK: Command expired, discarding');
        _prefs!.remove(key);
        return;
      }

      if (action == null || action.isEmpty) {
        _logDebug('⚠️ CMD_CHECK: Command missing action field, ignoring');
        _prefs!.remove(key);
        return;
      }

      await _handlePlaybackCommand(action, params);
      handled = true;
    } catch (e) {
      _logDebug('❌ CMD_CHECK: Error parsing command: $e');
    } finally {
      try {
        await _prefs!.remove(key);
      } catch (removeError) {
        _logDebug('⚠️ CMD_CHECK: Failed to clear command key: $removeError');
      }

      if (handled) {
        await notifyPlaybackChanged();
      }
    }
  }
  
  /// Handle playback commands from Android Auto
  Future<void> _handlePlaybackCommand(
    String action,
    Map<String, dynamic> params,
  ) async {
    if (_audioService == null) {
      _logDebug('❌ CMD_ERROR: audioService is null, cannot execute $action');
      return;
    }
    
    _logDebug('🎮 EXECUTING CMD: $action (params: $params)');
    
    try {
      switch (action) {
        case 'play':
          _logDebug('▶️ Calling audioService.play()');
          await _audioService!.play(propagateToNative: false);
          _logDebug('✅ Play command completed');
          await notifyPlaybackChanged();
          break;
          
        case 'pause':
          await _audioService!.pause(propagateToNative: false);
          await notifyPlaybackChanged();
          break;
          
        case 'skipToNext':
          await _audioService!.skipToNext(propagateToNative: false);
          await notifyPlaybackChanged();
          break;
          
        case 'skipToPrevious':
          await _audioService!.skipToPrevious(propagateToNative: false);
          await notifyPlaybackChanged();
          break;
          
        case 'seekTo':
          final position = params['position'] as int?;
          if (position != null) {
            await _audioService!.seek(
              Duration(milliseconds: position),
              propagateToNative: false,
            );
            await notifyPlaybackChanged();
          }
          break;
          
        case 'setSpeed':
          final speed = params['speed'] as double?;
          if (speed != null) {
            await _audioService!.setSpeed(speed);
            await notifyPlaybackChanged();
          }
          break;
          
        case 'playFromMediaId':
          final mediaId = params['mediaId'] as String?;
          if (mediaId != null) {
            await _handlePlayFromMediaId(mediaId);
            await notifyPlaybackChanged();
          }
          break;
          
        case 'playFromSearch':
          final query = params['query'] as String?;
          if (query != null) {
            await _handlePlayFromSearch(query);
            await notifyPlaybackChanged();
          }
          break;
          
        default:
          _logDebug('Unknown command: $action');
      }
 
    } catch (e) {
      _logDebug('Error handling command $action: $e');
    }
  }
  
  /// Handle play from media ID command
  Future<void> _handlePlayFromMediaId(String mediaId) async {
    if (_audiobookProvider == null || _audioService == null) {
      _logDebug('❌ PLAY_FROM_ID: Cannot play - provider or service is null');
      return;
    }
    
    _logDebug('📻 PLAY_FROM_ID: $mediaId');
    
    try {
      // Parse media ID
      if (mediaId.startsWith('chapter_')) {
        // Direct chapter playback
        final chapterId = mediaId.replaceFirst('chapter_', '');
        
        // Find the audiobook containing this chapter
        for (final book in _audiobookProvider!.audiobooks) {
          final chapterIndex = book.chapters.indexWhere((c) => c.id == chapterId);
          if (chapterIndex != -1) {
            // Load audiobook and play from this chapter
            await _audioService!.loadAudiobook(
              book,
              startChapter: chapterIndex,
              autoPlay: true,
              propagateCommands: false,
            );
            break;
          }
        }
      } else if (mediaId.startsWith('book_')) {
        // Book playback from beginning or last position
        final bookId = mediaId.replaceFirst('book_', '');
        _logDebug('📖 Loading book with ID: $bookId');
        
        // CRITICAL FIX #2: Validate audiobooks list is not empty before accessing
        if (_audiobookProvider!.audiobooks.isEmpty) {
          _logDebug('❌ CRITICAL: Cannot play - no audiobooks in library');
          _logDebug('💡 User needs to add audiobooks before playback can start');
          return; // Exit gracefully instead of crashing
        }
        
        // Find book by ID with safe fallback
        final book = _audiobookProvider!.audiobooks.firstWhere(
          (b) => b.id == bookId,
          orElse: () {
            _logDebug('⚠️ Book ID $bookId not found, using first available book');
            return _audiobookProvider!.audiobooks.first; // Safe now that we validated non-empty
          },
        );
        
        _logDebug('📖 Found book: ${book.title}');
        
        // Get last position
        final lastPosition = await _storageService?.loadLastPosition(book.id);
        _logDebug('📍 Last position: $lastPosition');
        
        if (lastPosition != null) {
          _logDebug('▶️ Loading with saved chapterId=${lastPosition['chapterId']} position=${lastPosition['position']}');
          final chapterId = lastPosition['chapterId'] as String?;
          final savedPosition = lastPosition['position'] as Duration?;

          await _audioService!.loadAudiobook(
            book,
            startChapter: _resolveChapterIndex(book, chapterId),
            startPosition: savedPosition,
            autoPlay: true,
            propagateCommands: false,
          );
        } else {
          _logDebug('▶️ Loading from beginning, autoPlay=true');
          await _audioService!.loadAudiobook(
            book,
            autoPlay: true,
            propagateCommands: false,
          );
        }
        _logDebug('✅ Book loaded and playing');
      }
    } catch (e) {
      _logDebug('Error playing from media ID: $e');
    }
  }
  
  /// Handle play from search command
  Future<void> _handlePlayFromSearch(String query) async {
    if (_audiobookProvider == null || _audioService == null) return;
    
    _logDebug('Play from search: $query');
    
    try {
      // ADDITIONAL FIX #2: Validate audiobooks exist before searching
      if (_audiobookProvider!.audiobooks.isEmpty) {
        _logDebug('❌ Cannot search - no audiobooks in library');
        return;
      }
      
      final lowerQuery = query.toLowerCase();
      
      // Search for matching audiobook
      final matchingBook = _audiobookProvider!.audiobooks.firstWhere(
        (book) {
          final title = _audiobookProvider!.getTitleForAudiobook(book).toLowerCase();
          final author = (book.author ?? '').toLowerCase();
          return title.contains(lowerQuery) || author.contains(lowerQuery);
        },
        orElse: () => _audiobookProvider!.audiobooks.first, // Safe after validation
      );
      
      // Get last position
      final lastPosition = await _storageService?.loadLastPosition(matchingBook.id);
      
      if (lastPosition != null) {
        await _audioService!.loadAudiobook(
          matchingBook,
          startChapter: _resolveChapterIndex(matchingBook, lastPosition['chapterId'] as String?),
          startPosition: lastPosition['position'] as Duration?,
          autoPlay: true,
          propagateCommands: false,
        );
      } else {
        await _audioService!.loadAudiobook(
          matchingBook,
          autoPlay: true,
          propagateCommands: false,
        );
      }
    } catch (e) {
      _logDebug('Error playing from search: $e');
    }
  }
  
  /// Force immediate sync (call when significant data changes)
  Future<void> forceSyncNow() async {
    if (!_initialized) return;
    await syncDataToNative();
  }
  
  /// Notify Android Auto of audiobook library changes
  Future<void> notifyLibraryChanged() async {
    await forceSyncNow();
  }
  
  /// Notify Android Auto of playback state changes
  Future<void> notifyPlaybackChanged() async {
    await _syncPlaybackState();
  }
  
  /// Debug logging
  void _logDebug(String message) {
    if (kDebugMode) {
      debugPrint('[$_logPrefix] $message');
    }
  }

  int _resolveChapterIndex(Audiobook book, String? chapterId) {
    if (chapterId == null || chapterId.isEmpty) {
      return 0;
    }
    final idx = book.chapters.indexWhere((c) => c.id == chapterId);
    return idx == -1 ? 0 : idx;
  }
}


