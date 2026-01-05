import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/audiobook.dart';
import '../services/storage_service.dart';
import '../services/statistics_service.dart';
import '../services/engagement_manager.dart';
import '../services/widget_service.dart';
import '../services/pulse_sync_service.dart';

class SimpleAudioService with WidgetsBindingObserver {
  // Singleton instance
  static final SimpleAudioService _instance = SimpleAudioService._internal();
  factory SimpleAudioService() => _instance;

  // Method channel for Android Auto MediaSession updates
  static const _audioBridgeChannel = MethodChannel('com.widdlereader.app/audio_bridge');

  // Internal player & effects
  late final AudioPlayer _player;
  AndroidEqualizer? _equalizer;
  AndroidLoudnessEnhancer? _loudnessEnhancer;

  // Audio session
  AudioSession? _audioSession;
  bool _notificationsEnabled = false;

  // Current audiobook info
  Audiobook? _currentAudiobook;
  int _currentChapterIndex = 0;

  // Stream controllers
  final _positionSubject = BehaviorSubject<Duration>.seeded(Duration.zero);
  final _durationSubject = BehaviorSubject<Duration>.seeded(Duration.zero);
  final _currentChapterSubject = BehaviorSubject<int>.seeded(0);
  final _playingSubject = BehaviorSubject<bool>.seeded(false);
  final _speedSubject = BehaviorSubject<double>.seeded(1.0);
  final _errorSubject = PublishSubject<String>(); // Broadcaster for playback errors
  final _audiobookSubject = BehaviorSubject<Audiobook?>.seeded(null);

  // Timer for auto-saving
  Timer? _autoSaveTimer;
  final StorageService _storageService = StorageService();
  final StatisticsService _statsService = StatisticsService();
  final WidgetService _widgetService = WidgetService();

  // Timer for MediaSession updates
  Timer? _mediaSessionUpdateTimer;

  // Add this flag to track user intent
  bool _userPaused = false;

  // Add this flag to track restore state
  bool _isRestoring = false;

  // Stream getters
  Stream<Duration> get positionStream => _positionSubject.stream;
  Stream<Duration> get durationStream => _durationSubject.stream;
  Stream<int> get currentChapterStream => _currentChapterSubject.stream;
  Stream<bool> get playingStream => _playingSubject.stream;
  Stream<double> get speedStream => _speedSubject.stream;
  Stream<Audiobook?> get audiobookStream => _audiobookSubject.stream;
  Stream<String> get errorStream => _errorSubject.stream;

  // Current state getters
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  bool get isPlaying => _player.playing;
  int get currentChapterIndex => _currentChapterIndex;
  Audiobook? get currentAudiobook => _currentAudiobook;
  double get speed => _player.speed;

  // Private constructor
  SimpleAudioService._internal() {
    // Initialize audio pipeline (Android only effects)
    _equalizer = AndroidEqualizer();
    _loudnessEnhancer = AndroidLoudnessEnhancer();
    
    _player = AudioPlayer(
      audioPipeline: AudioPipeline(
        androidAudioEffects: [
          if (_equalizer != null) _equalizer!,
          if (_loudnessEnhancer != null) _loudnessEnhancer!,
        ],
      ),
    );

    // Explicitly disable on init to prevent muting before book load
    _equalizer?.setEnabled(false);
    _loudnessEnhancer?.setEnabled(false);

    WidgetsBinding.instance.addObserver(this);
    _initStreams();
    _initAudioSession();
    _storageService.addRestoreListener(_onDataRestored);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      debugPrint('📱 App Lifecycle: $state - Forcing save...');
      // Force synchronous-like save when app is backgrounded/killed
      if (_currentAudiobook != null && _player.playing) {
        saveCurrentPosition();
        _statsService.syncCurrentSession();
      }
    }
  }

  void _onDataRestored() async {
    debugPrint("Data restore detected! Emergency stopping playback...");
    _isRestoring = true;
    
    // Cancel auto-save to prevent overwriting restored data
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    
    // Cancel MediaSession update timer
    _mediaSessionUpdateTimer?.cancel();
    _mediaSessionUpdateTimer = null;
    
    // Stop player without saving
    await _player.stop();
    
    // Clear native MediaSession to prevent stale notification controls
    try {
      await _audioBridgeChannel.invokeMethod('clearMediaSession');
      debugPrint("Native MediaSession cleared successfully");
    } catch (e) {
      debugPrint("Error clearing native MediaSession: $e - continuing anyway");
    }
    
    // Clear state
    _currentAudiobook = null;
    _currentChapterIndex = 0;
    _userPaused = false;
    
    // Update streams to reflect 'stopped/empty' state
    _currentChapterSubject.add(0);
    _playingSubject.add(false);
    _audiobookSubject.add(null); // Notify UI components to clear stale references
    
    // Reset restoring flag after a short delay to ensure stop() events have processed
    Future.delayed(const Duration(milliseconds: 1000), () {
      _isRestoring = false;
      debugPrint("Restore flag cleared - ready for new playback");
    });
  }

  // Public initialization method for explicit init when needed
  void init() {
    // Only initialize if needed
    if (_audioSession == null) {
      _initAudioSession();
    }
    
    // Start auto-save timer for playback position
    _startAutoSaveTimer();
  }

  void _initStreams() {
    // Position updates
    _player.positionStream.listen((position) {
      _positionSubject.add(position);
    });

    // Duration updates
    _player.durationStream.listen((duration) {
      if (duration != null) {
        _durationSubject.add(duration);
      }
    });

    // Playing state updates - CENTRALIZED LOGIC FOR STATS & SAVING
    _player.playingStream.listen((playing) {
      _playingSubject.add(playing);
      
      if (playing) {
        _startMediaSessionUpdates();
        
        // Start stats session if not already active and we have a book
        // This handles "Play" from ANY source (UI, Notification, Headset)
        if (_currentAudiobook != null && !_isRestoring) {
             debugPrint('▶️ Playback detected (Stream) - ensuring stats session active');
             
             // 1. Start AutoSave Timer
             _startAutoSaveTimer();
             
             // 2. Start Stats Session if needed
             if (!_statsService.hasActiveSession) {
                final chapterName = _currentAudiobook!.chapters[_currentChapterIndex].title;
                _statsService.startSession(
                  audiobookId: _currentAudiobook!.id,
                  chapterName: chapterName,
                );
             }
             
             // 3. CRITICAL: Apply EQ settings NOW that audio session is truly active
             // This fixes the mute bug on app restart with EQ enabled
             _applyEqOnPlaybackStart();
             
             // 4. Update home screen widget with current book/chapter
             _updateHomeWidget(isPlaying: true);
        }
      } else {
        _stopMediaSessionUpdates();
        
        // Handle Pause/Stop from ANY source
        // Auto-save when playback stops (covers notification pause, headset disconnect, etc.)
        // But ONLY if we aren't in the middle of a restore!
        if (!_isRestoring) {
          debugPrint('⏸️ Pause detected (Stream) - saving and closing session');
          
          // 1. Save Position
          saveCurrentPosition();
          
          // 2. End Stats Session
          // critical: ensure we close the session so time stops tracking
          _statsService.endSession();
          
          // 3. Cancel Timer
          _autoSaveTimer?.cancel();
          _autoSaveTimer = null;
          
          // 4. Reset EQ flag so it re-applies if the session was lost/reset
          _eqAppliedThisSession = false;
          
          // 5. Update home screen widget to show paused state
          _updateHomeWidget(isPlaying: false);

          // 6. Pulse out on pause
          PulseSyncService().pulseOut();
        }
      }
      _updateMediaSessionPlaybackState();
    });

    // Speed updates
    _player.speedStream.listen((speed) {
      _speedSubject.add(speed);
      _updateMediaSessionPlaybackState();
    });
    
    // ERROR LISTENER - CRITICAL for diagnosing "buttons don't work"
    _player.playbackEventStream.listen((event) {
      // Nothing needed here usually, but it confirms events are flowing
    }, onError: (Object e, StackTrace stackTrace) {
      debugPrint('🚨 [just_audio] Error detected in playback stream: $e');
      debugPrint('$stackTrace');
    });

    _player.processingStateStream.listen((state) {
      debugPrint('📊 [PlayerState] ProcessingState changed to: $state');
      if (state == ProcessingState.completed) {
        debugPrint('🏁 [PlayerState] Chapter completed, skipping to next...');
        skipToNext();
      }
    });
    
    // Listen for media button events from notifications
    _player.androidAudioSessionIdStream.listen((_) {
      _notificationsEnabled = true;
      debugPrint("Android audio session connected - notifications enabled");
    });
    
    // Process notification actions
    _player.sequenceStateStream.listen((sequenceState) {
      if (sequenceState != null) {
        // If the sequence state changes, it might be due to notification controls
        debugPrint("Sequence state changed by notification controls");
      }
    });
  }

  // Initialize audio session
  Future<void> _initAudioSession() async {
    try {
      _audioSession = await AudioSession.instance;
      await _audioSession!.configure(const AudioSessionConfiguration.music());

      // Set up callbacks for audio interruptions
      _audioSession!.interruptionEventStream.listen((event) async {
        if (event.begin) {
          // Audio interrupted - pause playback
          if (event.type == AudioInterruptionType.duck) {
            // Lower volume temporarily
            _player.setVolume(0.5);
          } else {
            // Store current state before pausing
            bool wasPlaying = _player.playing;
            
            // CRITICAL: Explicitly save everything BEFORE pausing
            // This ensures data is safe even if app is backgrounded/killed shortly after
            if (wasPlaying) {
               debugPrint('🔊 Audio Interruption: Explicitly saving state...');
               await saveCurrentPosition();
               await _statsService.syncCurrentSession();
            }

            // Pause playback
            await pause();
            
            // Remember if we were playing before the interruption
            _userPaused = !wasPlaying;
          }
        } else {
          // Interruption ended
          if (event.type == AudioInterruptionType.duck) {
            // Restore volume
            _player.setVolume(1.0);
          } else if (!_userPaused) {
            // Only auto-resume if pause wasn't user-initiated
            // and notifications are enabled (system is expecting us to handle media)
            if (_notificationsEnabled && !_userPaused) {
              play();
            }
          }
        }
      });
      
      // Set up callbacks for media button events
      _audioSession!.becomingNoisyEventStream.listen((_) {
        // Headphones unplugged or other noise-creating event
        pause();
      });
      
      // Add a listener to player state changes to better handle media button events
      _player.playerStateStream.listen((state) {
        // Update state changes to handle media keys correctly
        debugPrint("Player state changed: ${state.processingState}, playing: ${state.playing}");
      });

      debugPrint("Audio session initialized successfully");
    } catch (e) {
      debugPrint("Error initializing audio session: $e");
    }
  }

  // Method to keep the service alive when screens change
  Future<void> detachFromUI() async {
    // This method can be called when user navigates away
    // We'll just ensure any UI-specific operations are stopped
    debugPrint("Audio service detached from UI, continuing playback");
  }

  // Enable notifications
  Future<void> enableNotifications() async {
    if (_notificationsEnabled) return;

    try {
      if (_currentAudiobook == null) {
        debugPrint("Cannot enable notifications without an audiobook loaded");
        return;
      }

      // Ensure current chapter is properly configured with a MediaItem
      // This will automatically enable system media controls
      await loadChapter(_currentChapterIndex, startPosition: _player.position);
      
      _notificationsEnabled = true;
      debugPrint("Media notifications enabled successfully");
      
      // Add specific handler for media button commands
      _player.processingStateStream.listen((state) {
        if (state == ProcessingState.completed) {
          skipToNext();
        }
      });
      
      // Handle skip actions from notification controls
      _player.sequenceStateStream.where((state) => state != null).listen((state) {
        // The player's sequence state is updated when notification controls are used
        debugPrint("Media controls used via notification");
      });
      
      debugPrint("Next/previous buttons in notifications enabled");
    } catch (e) {
      debugPrint("Error enabling notifications: $e");
    }
  }

  // Add method to safely stop current playback
  Future<void> stopCurrentPlayback() async {
    debugPrint('📊 [StopCurrentPlayback] Cleaning up session...');
    
    // 1. Force stop the stats timer
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;

    // 2. Force end any active statistics session
    // This is critical when switching books to prevent phantom time
    try {
      if (_statsService.hasActiveSession) {
        debugPrint('📊 Force ending active stats session during stop/switch');
        await _statsService.endSession();
      }
    } catch (e) {
      debugPrint('Error ending stats session during stop: $e');
    }

    if (_currentAudiobook != null && _player.playing) {
      await saveCurrentPosition();
      await _player.pause();
      _userPaused = true; // Mark as explicitly paused
    }
    
    // Pulse out on stop
    PulseSyncService().pulseOut();
  }

  // Load an audiobook
  Future<void> loadAudiobook(
    Audiobook audiobook, {
    int startChapter = 0,
    Duration? startPosition,
    bool autoPlay = false, // Default to false
    bool propagateCommands = true,
  }) async {
    try {
      // If we're already playing this audiobook, don't interrupt
      if (_currentAudiobook?.id == audiobook.id && _player.playing) {
        debugPrint("Already playing this audiobook, continuing playback");
        return;
      }

      // Stop any current playback
      await stopCurrentPlayback();
      
      // Reset EQ session flag for fresh application
      _eqAppliedThisSession = false;

      _currentAudiobook = audiobook;
      _audiobookSubject.add(audiobook); // Notify UI components of new audiobook
      _currentChapterIndex = startChapter.clamp(
        0,
        audiobook.chapters.length - 1,
      );

      final storedSpeed = await _storageService.getPlaybackSpeed(audiobook.id);
      if (storedSpeed != null && storedSpeed != _player.speed) {
        await _player.setSpeed(storedSpeed);
        _speedSubject.add(storedSpeed);
      }

      await loadChapter(_currentChapterIndex, startPosition: startPosition);
      debugPrint("Loaded audiobook: ${audiobook.title}");
      
      // Apply per-book EQ settings
      await applyBookEqualizerSettings();

      // Only auto-play if explicitly requested
      if (autoPlay) {
        await play(propagateToNative: propagateCommands);
      }
      
      // Update home screen widget
      await _updateHomeWidget(isPlaying: autoPlay);
    } catch (e) {
      debugPrint("Error loading audiobook: $e");
      rethrow;
    }
  }

  // Helper method to save cover art to temporary file
  Future<Uri?> _getCoverArtUri(Uint8List coverArt, String id) async {
    try {
      final tempDir = await getTemporaryDirectory();
      // FIX: Use hash for filename to prevent filesystem errors with long IDs
      // We use hashCode as a simple, short unique identifier for temp files
      final safeName = 'cover_${id.hashCode}'; 
      final file = File('${tempDir.path}/$safeName.jpg');
      
      // Optimized: Only write if didn't exist to save IO
      if (!await file.exists()) {
        await file.writeAsBytes(coverArt);
      }
      return Uri.file(file.path);
    } catch (e) {
      debugPrint("Error creating cover art file: $e");
      // Fallback to data URI (though AA support is limited)
      return Uri.dataFromBytes(coverArt);
    }
  }

  // Tracking generation for robust EQ re-enabling during rapid chapter switches
  int _eqLoadGeneration = 0;

  // Load a chapter by index
  Future<void> loadChapter(int index, {Duration? startPosition}) async {
    if (_currentAudiobook == null ||
        index < 0 ||
        index >= _currentAudiobook!.chapters.length) {
      throw Exception("Invalid chapter index: $index");
    }

    // Increment generation to cancel any previous pending re-enables
    _eqLoadGeneration++;
    final currentGeneration = _eqLoadGeneration;
    
    // Reset EQ session flag so it re-applies on next play
    _eqAppliedThisSession = false;

    try {
      final chapter = _currentAudiobook!.chapters[index];
      
      // Validate file
      final audioPath = chapter.sourcePath;
      final isContentUri = audioPath.startsWith('content://');
      
      if (!isContentUri) {
        final audioFile = File(audioPath);
        if (!await audioFile.exists()) {
          throw Exception("Audio file not found: ${audioFile.path}");
        }
        
        final fileSize = await audioFile.length();
        if (fileSize < 1024) {
          throw Exception("Audio file appears corrupted (too small): ${audioFile.path}");
        }
      }
      
      debugPrint("📖 [LoadChapter] Loading chapter $index: ${chapter.title} from $audioPath");

      // Prepare artUri - prioritize cached cover art (reliable local file)
      Uri? artUri;
      try {
        final coverPath = await _storageService.getCachedCoverArtPath(_currentAudiobook!.id);
        if (coverPath != null && await File(coverPath).exists()) {
          artUri = Uri.file(coverPath);
          debugPrint("🖼️ [LoadChapter] Using cached cover art: $coverPath");
        } else if (_currentAudiobook!.coverArt != null) {
          final sanitizedId = _currentAudiobook!.id.replaceAll(RegExp(r'[^\w]'), '_');
          artUri = await _getCoverArtUri(_currentAudiobook!.coverArt!, sanitizedId);
          debugPrint("🖼️ [LoadChapter] Using in-memory cover art (saved to temp)");
        } else {
          debugPrint("🖼️ [LoadChapter] No cover art available for this book");
        }
      } catch (e) {
        debugPrint("Error getting cover art URI: $e");
      }
      
      // Create MediaItem
      final mediaItem = MediaItem(
        id: chapter.id,
        album: _currentAudiobook!.title,
        title: chapter.title,
        artist: _currentAudiobook!.author ?? _currentAudiobook!.title,
        artUri: artUri,
        duration: chapter.duration,
        displayTitle: chapter.title,
        displaySubtitle: _currentAudiobook!.title,
        displayDescription: _currentAudiobook!.author ?? _currentAudiobook!.title,
        extras: {
          'audiobookId': _currentAudiobook!.id,
          'chapterIndex': index,
          'totalChapters': _currentAudiobook!.chapters.length,
          'bookTitle': _currentAudiobook!.title,
          'hasPrevious': index > 0,
          'hasNext': index < _currentAudiobook!.chapters.length - 1,
        },
      );

      // Set Audio Source
      try {
        AudioSource audioSource;
        
        if (chapter.end != null && chapter.end! > Duration.zero && chapter.end! > chapter.start) {
          audioSource = ClippingAudioSource(
              child: AudioSource.uri(
                isContentUri ? Uri.parse(audioPath) : Uri.file(audioPath), 
                tag: mediaItem
              ),
              start: chapter.start,
              end: chapter.end,
              tag: mediaItem,
          );
        } else {
          audioSource = AudioSource.uri(
            isContentUri ? Uri.parse(audioPath) : Uri.file(audioPath), 
            tag: mediaItem
          );
        }

        // IMPROVEMENT: Robustness fix for EQ muting/state issues.
        final intendedEqEnabled = await _storageService.getEqualizerEnabled(audiobookId: _currentAudiobook!.id);
        final intendedBoost = await _storageService.getVolumeBoost(audiobookId: _currentAudiobook!.id);
        final shouldApplyEffects = intendedEqEnabled || (intendedBoost > 0.01);

        // ONLY disable briefly if it's a new book to avoid hardware glitches.
        final isNewBook = _lastAppliedBookId != _currentAudiobook!.id;
        if (shouldApplyEffects && isNewBook) {
          debugPrint('📊 New book detected, briefly cycling EQ for hardware reset');
          await _equalizer?.setEnabled(false);
          await _loudnessEnhancer?.setEnabled(false);
        }

        debugPrint('🕒 [LoadChapter] Setting AudioSource (Position: $startPosition)...');
        await _player.setAudioSource(audioSource, initialPosition: startPosition)
            .timeout(const Duration(seconds: 15), onTimeout: () {
              debugPrint('🚨 [LoadChapter] TIMEOUT setting audio source!');
              throw Exception("Timeout loading audio source. This can happen with slow storage or SAF indexing issues.");
            });
        debugPrint('✅ [LoadChapter] AudioSource set successfully. Duration: ${_player.duration}');
        
        // REMOVED: EQ application is now deferred to playback start
        // See _applyEqOnPlaybackStart() in playingStream listener
        // This prevents the mute bug caused by enabling EQ before audio session is active
        // _applyEqOnPlaybackStart(); 
      } catch (audioSourceError) {
        if (audioSourceError.toString().contains('FileSystemException')) {
          throw Exception("Cannot access audio file. Check file permissions.");
        } else if (audioSourceError.toString().contains('FormatException') || 
                   audioSourceError.toString().contains('Unsupported')) {
          throw Exception("Unsupported audio format or corrupted file.");
        } else if (audioSourceError.toString().contains('NetworkException')) {
          throw Exception("File access error (may be on unavailable drive).");
        } else {
          throw Exception("Failed to load audio file: $audioSourceError");
        }
      }

      _currentChapterIndex = index;
      _currentChapterSubject.add(index);
      
      // Restore playback speed for this book
      final savedSpeed = await _storageService.getPlaybackSpeed(_currentAudiobook!.id);
      final speedToUse = savedSpeed ?? 1.0;
      await _player.setSpeed(speedToUse);
      _speedSubject.add(speedToUse);
      
      debugPrint("Successfully loaded chapter: ${chapter.title} with speed: $speedToUse");
      
      // Pass the artUri string (convert from Uri object if available)
      String? artUriString;
      if (artUri != null) {
        if (artUri.scheme == 'file') {
          artUriString = artUri.toFilePath();
        } else {
          artUriString = artUri.toString();
        }
      }
      
      await _updateMediaSessionMetadata(overrideArtUri: artUriString);
      await _updateMediaSessionPlaybackState();

      // Record engagement for streak tracking
      unawaited(EngagementManager().recordListeningSession());
      
      // Update home screen widget
      await _updateHomeWidget(isPlaying: _player.playing);
    } catch (e) {
      debugPrint("🚨 [LoadChapter] CRITICAL ERROR loading chapter $index: $e");
      _errorSubject.add("Failed to load chapter: $e");
      
      String userMessage = "Failed to load chapter.";
      if (e.toString().contains("not found")) {
        userMessage = "Audio file not found. The file may have been moved or deleted.";
      } else if (e.toString().contains("corrupted")) {
        userMessage = "Audio file appears to be corrupted.";
      } else if (e.toString().contains("permissions")) {
        userMessage = "Cannot access audio file. Check file permissions.";
      } else if (e.toString().contains("Unsupported") || e.toString().contains("format")) {
        userMessage = "Unsupported audio format.";
      } else if (e.toString().contains("unavailable drive")) {
        userMessage = "Audio file is on an unavailable drive or storage device.";
      }
      
      throw Exception(userMessage);
    }
  }

  // Method to start a timer that auto-saves position periodically
  void _startAutoSaveTimer() {
    // Cancel existing timer if any
    _autoSaveTimer?.cancel();
    
    // Create a new timer that saves position every 10 seconds
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_currentAudiobook != null && isPlaying) {
        debugPrint("📊 [AutoSave] Saving position and syncing stats...");
        saveCurrentPosition();
        
        // Self-healing: Ensure stats session is active
        if (!_statsService.hasActiveSession) {
          debugPrint("📊⚠️ No active stats session found during playback - Auto-Recovering...");
          final chapterName = _currentAudiobook!.chapters[_currentChapterIndex].title;
          _statsService.startSession(
            audiobookId: _currentAudiobook!.id,
            chapterName: chapterName,
          );
        }
        
        _statsService.syncCurrentSession();
      }
    });
  }

  // Update MediaSession metadata (call when chapter loads)
  Future<void> _updateMediaSessionMetadata({String? overrideArtUri}) async {
    if (_currentAudiobook == null) return;
    
    try {
      final chapter = _currentAudiobook!.chapters[_currentChapterIndex];
      final duration = chapter.duration ?? _player.duration ?? Duration.zero;
      
      // Get cover art URI: Use override if provided, otherwise check storage
      String? artUri = overrideArtUri;
      if (artUri == null) {
         artUri = await _storageService.getCoverArtUri(_currentAudiobook!.id);
      }
      
      await _audioBridgeChannel.invokeMethod('updateMetadata', {
        'mediaId': _currentAudiobook!.id,
        'title': _currentAudiobook!.title,
        'artist': _currentAudiobook!.author ?? _currentAudiobook!.title,
        'album': _currentAudiobook!.title,
        'duration': duration.inMilliseconds,
        'artUri': artUri,
        'chapterTitle': chapter.title,
        'displayTitle': _currentAudiobook!.title,
        'displaySubtitle': chapter.title,
        'displayDescription': _currentAudiobook!.author ?? _currentAudiobook!.title,
      });
      
      debugPrint("Updated Android Auto metadata: ${chapter.title} (Art: $artUri)");
    } catch (e) {
      debugPrint("Error updating MediaSession metadata: $e");
    }
  }

  // Update MediaSession playback state (call periodically during playback)
  Future<void> _updateMediaSessionPlaybackState() async {
    if (_currentAudiobook == null) return;
    
    try {
      final hasNext = _currentChapterIndex < _currentAudiobook!.chapters.length - 1;
      final hasPrevious = _currentChapterIndex > 0;
      
      await _audioBridgeChannel.invokeMethod('updatePlaybackState', {
        'position': _player.position.inMilliseconds.toInt(),  // Ensure it's sent as int64
        'isPlaying': _player.playing,
        'speed': _player.speed,
        'hasNext': hasNext,
        'hasPrevious': hasPrevious,
      });
      
      debugPrint("Updated Android Auto playback state");
    } catch (e) {
      debugPrint("Error updating MediaSession playback state: $e");
    }
  }

  // Start periodic MediaSession updates
  void _startMediaSessionUpdates() {
    // Cancel existing timer if any
    _mediaSessionUpdateTimer?.cancel();
    
    // Update immediately
    _updateMediaSessionPlaybackState();
    
    // Then update every 1 second for smooth seek bar
    _mediaSessionUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_currentAudiobook != null) {
        _updateMediaSessionPlaybackState();
      }
    });
  }

  // Stop periodic MediaSession updates
  void _stopMediaSessionUpdates() {
    _mediaSessionUpdateTimer?.cancel();
    _mediaSessionUpdateTimer = null;
    
    // Send final update with paused state
    _updateMediaSessionPlaybackState();
  }

  // Enhanced position saving
  Future<Map<String, dynamic>> _saveCurrentPosition({
    bool silent = false,
    bool isFinishing = false,
  }) async {
    if (_currentAudiobook == null) {
      return {};
    }

    final position = _player.position;
    final audiobookId = _currentAudiobook!.id;
    final chapterId = _currentAudiobook!.chapters[_currentChapterIndex].id;

    try {
      // If isFinishing is true, we're moving to a new chapter, so save the position as 0
      final positionToSave = isFinishing ? Duration.zero : position;
      
      await _storageService.saveLastPosition(audiobookId, chapterId, positionToSave);

      if (!silent) {
        debugPrint("Saved position for $audiobookId: $chapterId at $positionToSave");
      }

      return {
        'audiobookId': audiobookId,
        'chapterId': chapterId,
        'position': positionToSave,
      };
    } catch (e) {
      debugPrint("Error saving position: $e");
      return {};
    }
  }

  // Method to set playback speed
  Future<void> setSpeed(double speed) async {
    final normalizedSpeed = speed.clamp(0.5, 3.0);
    // User requested wall-clock tracking, so stats update is removed
    await _player.setSpeed(normalizedSpeed);
    _speedSubject.add(normalizedSpeed);
    if (_currentAudiobook != null) {
      await _storageService.savePlaybackSpeed(
        _currentAudiobook!.id,
        normalizedSpeed,
      );
    }
    debugPrint("Playback speed set to: $normalizedSpeed");
  }

  // Playback controls with user intent tracking
  Future<void> play({bool propagateToNative = true}) async {
    // Guard against playing during restore
    if (_isRestoring) {
      debugPrint('Ignoring play request - data restore in progress');
      return;
    }
    
    if (_currentAudiobook == null) {
      debugPrint('Attempted to play with no audiobook loaded');
      return;
    }

    debugPrint('Attempting to play current audiobook...');
    _userPaused = false;
    if (!_player.playing) {
      try {
        await _player.play();
        debugPrint('Playback started successfully');
        
        // NOTE: Stats tracking and AutoSave are now handled in _initStreams
        // by listening to _player.playingStream. This ensures notifications work too.
        
        _notifyPlaybackChanged(nativeUpdate: true);
      } catch (error) {
        debugPrint('Error starting playback: $error');
      }
    } else {
      debugPrint('Playback already in progress, no action taken');
    }
  }

  Future<void> pause({bool propagateToNative = true}) async {
    if (!_player.playing) {
      debugPrint('Attempted to pause but player is already paused');
      return;
    }

    await _player.pause();
    debugPrint('Playback paused');
    _userPaused = true;
    
    // NOTE: Stats cleanup and AutoSave cancel are now handled in _initStreams
    
    _notifyPlaybackChanged(nativeUpdate: true);
  }

  Future<void> stop() async {
    await _player.stop();
    debugPrint('Playback stopped');
    _notifyPlaybackChanged(nativeUpdate: true);
  }

  Future<void> seek(
    Duration position, {
    bool fromUser = false,
    bool propagateToNative = true,
  }) async {
    debugPrint('🕒 [Seek] Seeking to ${position.inMilliseconds} ms (Player Status: ${_player.processingState})');
    await _player.seek(position);
    debugPrint('✅ [Seek] Seek finished');
    _notifyPlaybackChanged(nativeUpdate: true);
  }

  // Chapter navigation
  Future<void> skipToNext({bool propagateToNative = true}) async {
    if (_currentAudiobook == null) {
      debugPrint('skipToNext: No current audiobook');
      return;
    }

    final nextIndex = _currentChapterIndex + 1;
    if (nextIndex >= (_currentAudiobook?.chapters.length ?? 0)) {
      debugPrint('skipToNext: Already at last chapter, no action taken');
      return;
    }

    // Save current position before changing chapters
    await _saveCurrentPosition(isFinishing: true);
    
    await loadChapter(nextIndex);
    
    // Auto-play when skipping chapters
    await play(propagateToNative: propagateToNative);
    _notifyPlaybackChanged(nativeUpdate: true);
  }

  Future<void> skipToPrevious({bool propagateToNative = true}) async {
    if (_currentAudiobook == null) {
      debugPrint('skipToPrevious: No current audiobook');
      return;
    }

    final prevIndex = _currentChapterIndex - 1;
    if (prevIndex >= 0) {
      // Save current position before changing chapters
      await _saveCurrentPosition(isFinishing: true);
      
      // Load previous chapter and play it
      debugPrint("Skipping to previous chapter: $prevIndex");
      await loadChapter(prevIndex);
      
      // Ensure notifications are enabled when using media controls
      if (!_notificationsEnabled) {
        _notificationsEnabled = true;
      }
      
      // Auto-play when skipping chapters via notification controls
      await play(propagateToNative: propagateToNative);
    } else {
      debugPrint("Already at first chapter, cannot skip to previous");
      await _updateMediaSessionPlaybackState();
    }
  }

  Future<void> skipToChapter(int index, {bool propagateToNative = true}) async {
    if (_currentAudiobook == null) return;

    debugPrint('⏭️ [SkipToChapter] Navigating to chapter $index');
    if (index >= 0 && index < _currentAudiobook!.chapters.length) {
      await loadChapter(index);
      debugPrint('▶️ [SkipToChapter] Triggering play...');
      await play(propagateToNative: propagateToNative);
      if (propagateToNative) {
        _invokeMediaSessionCommand('skipToQueueItem', {
          'index': index,
        });
      }
    }
  }

  // Time skipping
  Future<void> fastForward({bool propagateToNative = true}) async {
    final currentPos = _player.position;
    final totalDuration = _player.duration;
    
    debugPrint('⏩ [FastForward] Current: $currentPos, Total: $totalDuration');
    
    if (totalDuration == null) {
      debugPrint('⚠️ [FastForward] Skipping because Duration is null');
      return;
    }

    final newPosition = currentPos + const Duration(seconds: 15);
    final maxPosition = totalDuration;

    await seek(
      newPosition > maxPosition ? maxPosition : newPosition,
      propagateToNative: propagateToNative,
    );
    await _updateMediaSessionPlaybackState();
  }

  Future<void> rewind({bool propagateToNative = true}) async {
    final currentPos = _player.position;
    debugPrint('⏪ [Rewind] Current: $currentPos');

    final newPosition = currentPos - const Duration(seconds: 15);
    await seek(
      newPosition < Duration.zero ? Duration.zero : newPosition,
      propagateToNative: propagateToNative,
    );
    await _updateMediaSessionPlaybackState();
  }

  // Save the current position for later resuming
  Future<Map<String, dynamic>> saveCurrentPosition() async {
    _autoSaveTimer?.cancel();
    await _updateMediaSessionPlaybackState();
    return await _saveCurrentPosition();
  }

  // Cleanup
  Future<void> dispose() async {
    _storageService.removeRestoreListener(_onDataRestored);
    _autoSaveTimer?.cancel();
    _mediaSessionUpdateTimer?.cancel();
    await _saveCurrentPosition(); // Save position one last time
    await _player.dispose();
    await _positionSubject.close();
    await _durationSubject.close();
    await _currentChapterSubject.close();
    await _playingSubject.close();
    await _speedSubject.close();
    await _errorSubject.close();
  }

  Future<void> _invokeMediaSessionCommand(String action, [Map<String, dynamic>? params]) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _audioBridgeChannel.invokeMethod('mediaSessionCommand', {
        'action': action,
        if (params != null) 'params': params,
      });
    } catch (e) {
      debugPrint('Error sending media session command "$action": $e');
    }
  }

  void _notifyPlaybackChanged({bool nativeUpdate = false}) {
    _updateMediaSessionPlaybackState();
    if (nativeUpdate) {
      _updateMediaSessionMetadata();
    }
  }

  // Public method to force sync state to native (e.g. for Android Auto connection)
  Future<void> forceSyncStateToNative() async {
    debugPrint("Forcing full state sync to native...");
    await _updateMediaSessionMetadata();
    await _updateMediaSessionPlaybackState();
  }

  /// Update the home screen widget with current playback state
  /// Update the home screen widget with current playback state
  Future<void> _updateHomeWidget({required bool isPlaying}) async {
    if (_currentAudiobook == null) {
      await _widgetService.clearWidget();
      return;
    }
    
    final bookTitle = _currentAudiobook!.title;
    final chapterTitle = _currentAudiobook!.chapters[_currentChapterIndex].title;
    
    // Get local cover art path
    String? coverPath;
    try {
      coverPath = await _storageService.getCachedCoverArtPath(_currentAudiobook!.id);
    } catch (e) {
      debugPrint("Error getting cover path for widget: $e");
    }
    
    await _widgetService.updateWidget(
      bookTitle: bookTitle,
      chapterTitle: chapterTitle,
      isPlaying: isPlaying,
      coverPath: coverPath,
    );
  }

  // ===========================
  // EQUALIZER & AUDIO EFFECTS (Per-Book)
  // ===========================

  /// Get current audiobook ID for per-book EQ
  String? get _currentEqBookId => _currentAudiobook?.id;

  Future<void> setEqualizerEnabled(bool enabled) async {
    if (_equalizer == null) return;
    await _equalizer!.setEnabled(enabled);
    await _storageService.saveEqualizerEnabled(enabled, audiobookId: _currentEqBookId);
    
    // Force a full re-apply to ensure bands and boost are in sync with settings
    if (enabled) {
      await applyBookEqualizerSettings(force: true);
    }
  }
  
  // Flag to track if EQ has been applied this playback session
  bool _eqAppliedThisSession = false;
  
  /// Apply EQ settings when playback actually starts
  /// This is the CORRECT time to enable EQ - when audio session is active
  void _applyEqOnPlaybackStart() {
    if (_currentAudiobook == null || _equalizer == null) return;
    if (_eqAppliedThisSession) return; // Only apply once per play session
    
    // DELAYED MARK: Don't set to true yet, wait for successful application
    
    // Reduced delay for snappier application
    Future.delayed(const Duration(milliseconds: 300), () async {
      if (!_player.playing) return;
      
      debugPrint('📊 [EQ] Snappy application on playback start');
      await applyBookEqualizerSettings(force: true);
      _eqAppliedThisSession = true;
    });
  }
  
  Future<bool> getEqualizerEnabled() async {
    if (_currentAudiobook != null) {
      return await _storageService.getEqualizerEnabled(audiobookId: _currentAudiobook!.id);
    }
    if (_equalizer == null) return false;
    return await _equalizer!.enabled;
  }

  Future<List<AndroidEqualizerBand>> getEqualizerBands() async {
    if (_equalizer == null) return [];
    final parameters = await _equalizer!.parameters;
    return parameters.bands;
  }

  // Timer for debouncing hardware updates to avoid flooding the DSP
  Timer? _eqDebounceTimer;

  /// Set all band gains at once (for presets)
  /// Bypasses the debounce timer to ensure all bands update immediately
  Future<void> setPresetGains(List<double> gains) async {
    if (_equalizer == null) return;
    
    // Cancel any pending single-band updates to prevent race conditions
    _eqDebounceTimer?.cancel();
    
    try {
      debugPrint('📊 Setting preset gains: $gains');
      
      // 1. Save to storage first
      for (int i = 0; i < gains.length; i++) {
        await _storageService.saveEqualizerBandGain(i, gains[i], audiobookId: _currentEqBookId);
      }
      
      // 2. Apply to hardware immediately
      if (await getEqualizerEnabled()) {
        // Ensure enabled on hardware
        if (!await _equalizer!.enabled) {
          await _equalizer!.setEnabled(true);
        }
        
        final parameters = await _equalizer!.parameters;
        final bands = parameters.bands;
        
        for (int i = 0; i < gains.length && i < bands.length; i++) {
          await bands[i].setGain(gains[i]);
        }
        
        // Nudge to ensure it takes effect immediately on some DSPs
        await _equalizer!.setEnabled(false);
        await _equalizer!.setEnabled(true);
      }
    } catch (e) {
      debugPrint('Error setting preset gains: $e');
    }
  }

  Future<void> setBandGain(int bandIndex, double gain) async {
    if (_equalizer == null) return;
    try {
      // Save instantly to storage for UI responsiveness
      await _storageService.saveEqualizerBandGain(bandIndex, gain, audiobookId: _currentEqBookId);
      
      // Debounce the hardware call
      _eqDebounceTimer?.cancel();
      _eqDebounceTimer = Timer(const Duration(milliseconds: 150), () async {
        final parameters = await _equalizer!.parameters;
        final bands = parameters.bands;
        if (bandIndex >= 0 && bandIndex < bands.length) {
          await bands[bandIndex].setGain(gain);
        }
      });
    } catch (e) {
      debugPrint('Error setting band gain: $e');
    }
  }

  /// Set generic volume boost (in decibels)
  Future<void> setVolumeBoost(double db) async {
    if (_loudnessEnhancer == null) return;
    
    // Save instantly
    await _storageService.saveVolumeBoost(db, audiobookId: _currentEqBookId);

    _eqDebounceTimer?.cancel();
    _eqDebounceTimer = Timer(const Duration(milliseconds: 150), () async {
      final isEqEnabled = await getEqualizerEnabled();
      
      // Enable if boosting AND master switch is on, disable otherwise
      if (db > 0.01 && isEqEnabled) {
        if (!await _loudnessEnhancer!.enabled) {
           await _loudnessEnhancer!.setEnabled(true);
        }
        await _loudnessEnhancer!.setTargetGain(db);
      } else {
        await _loudnessEnhancer!.setEnabled(false);
        await _loudnessEnhancer!.setTargetGain(0.0);
      }
    });
  }
  
  Future<double> getVolumeBoost() async {
    return await _storageService.getVolumeBoost(audiobookId: _currentEqBookId);
  }

  // Per-book EQ state cache to avoid redundant hardware calls
  String? _lastAppliedBookId;
  bool _isApplyingEq = false;

  /// Apply saved EQ settings for the current audiobook
  /// Extremely robust implementation to prevent mute/glitch on relaunch or transition
  Future<void> applyBookEqualizerSettings({bool force = false}) async {
    if (_currentAudiobook == null || _equalizer == null) return;
    
    final bookId = _currentAudiobook!.id;
    
    // We should NOT return early here because Android hardware effects often reset 
    // when a new audio source is loaded, even for the same book.
    // However, we still use the mutex to prevent concurrent applications.
    if (_isApplyingEq) {
      debugPrint('📊 EQ application in progress for $bookId, skipping redundant call');
      return;
    }
    
    _isApplyingEq = true;
    
    try {
      final settings = await _storageService.getBookEqualizerSettings(bookId);
      
      final enabled = settings['enabled'] as bool;
      final boost = settings['boost'] as double;
      final bandGains = settings['bands'] as Map<int, double>;
      
      debugPrint('📊 [EQ SYNC] Book: $bookId | Enable: $enabled | Boost: $boost | CustomBands: ${bandGains.length}');

      // 0. Force Reset if requested (Critical for fixing mute bugs)
      if (force) {
         await _equalizer?.setEnabled(false);
         await _loudnessEnhancer?.setEnabled(false);
         // Small pause to let the disable take effect
         await Future.delayed(const Duration(milliseconds: 50));
      }

      // 1. Prepare Hardware Parameters
      AndroidEqualizerParameters? parameters;
      int retries = 0;
      while (parameters == null && retries < 3) {
        try {
          parameters = await _equalizer!.parameters;
        } catch (e) {
          retries++;
          debugPrint('📊 [EQ SYNC] Retry $retries: Failed to fetch parameters: $e');
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      if (parameters == null) throw Exception("Failed to access hardware equalizer after retries");

      final bands = parameters.bands;

      // 2. ALWAYS reset all bands to 0.0 first to avoid ghost settings from other sessions/books
      for (var i = 0; i < bands.length; i++) {
        await bands[i].setGain(0.0);
      }

      // 3. Apply Saved Band Gains or Voice Clarity default if enabled
      if (enabled) {
         if (bandGains.isNotEmpty) {
           for (var i = 0; i < bands.length; i++) {
             if (bandGains.containsKey(i)) {
               final gain = bandGains[i]!;
               await bands[i].setGain(gain.clamp(-15.0, 15.0));
             }
           }
         } else {
            // Apply a subtle "Voice Clarity" boost if enabled but no custom bands
            debugPrint('📊 [EQ SYNC] Applying default Voice Clarity profile');
            // Most android equalizers have 5 bands. 
            // 60Hz, 230Hz, 910Hz, 3.6kHz, 14kHz approx.
            // Voice clarity: slightly cut low, boost mid-high (2-4kHz)
            if (bands.length >= 5) {
              await bands[0].setGain(-2.0); // 60Hz
              await bands[1].setGain(-1.0); // 230Hz
              await bands[2].setGain(1.0);  // 910Hz
              await bands[3].setGain(4.0);  // 3.6kHz (CRITICAL FOR VOICE)
              await bands[4].setGain(2.0);  // 14kHz
            }
         }
      }

      // 4. Handle Volume Boost (Loudness Enhancer)
      if (_loudnessEnhancer != null) {
        // Capped more tightly to avoid muting on some hardware
        final safeBoost = boost.clamp(0.0, 20.0);
        
        if (enabled && safeBoost > 0.01) {
          debugPrint('📊 [EQ SYNC] Applying boost: $safeBoost');
          // Important: set gain WHILE disabled, then enable
          await _loudnessEnhancer!.setEnabled(false);
          await _loudnessEnhancer!.setTargetGain(safeBoost);
          await Future.delayed(const Duration(milliseconds: 50));
          await _loudnessEnhancer!.setEnabled(true);
        } else {
          await _loudnessEnhancer!.setEnabled(false);
          await _loudnessEnhancer!.setTargetGain(0.0);
        }
      }
      
      // 5. SET ENABLED STATE LAST
      final currentEqEnabled = await _equalizer!.enabled;
      if (currentEqEnabled != enabled || force) {
        debugPrint('📊 [EQ SYNC] Setting hardware enabled: $enabled');
        await _equalizer!.setEnabled(enabled);
      }
      
      _lastAppliedBookId = bookId;
      debugPrint('📊 [EQ SYNC] ✅ SUCCESS for $bookId');
    } catch (e) {
      debugPrint('📊 [EQ SYNC] ❌ ERROR: $e');
      try {
        await _equalizer?.setEnabled(false);
      } catch (_) {}
    } finally {
      _isApplyingEq = false;
    }
  }
}
