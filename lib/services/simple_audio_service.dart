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
  final _audiobookSubject = BehaviorSubject<Audiobook?>.seeded(null);

  // Timer for auto-saving
  Timer? _autoSaveTimer;
  final StorageService _storageService = StorageService();
  final StatisticsService _statsService = StatisticsService();

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
    // Note: On iOS these will simply be ignored or need alternative implementation
    _equalizer = AndroidEqualizer();
    _loudnessEnhancer = AndroidLoudnessEnhancer();
    
    _player = AudioPlayer(
      audioPipeline: AudioPipeline(
        androidAudioEffects: [
          if (_loudnessEnhancer != null) _loudnessEnhancer!,
          if (_equalizer != null) _equalizer!,
        ],
      ),
    );

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
      _lastAppliedBookId = null; // Clear EQ cache to force re-apply after restore
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
        }
      }
      _updateMediaSessionPlaybackState();
    });

    // Speed updates
    _player.speedStream.listen((speed) {
      _speedSubject.add(speed);
      _updateMediaSessionPlaybackState();
    });

    // Completion listener - go to next chapter
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
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
      // EQ settings now restored per-book in loadAudiobook -> applyBookEqualizerSettings
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

    // 3. Stop player if playing
    if (_currentAudiobook != null && _player.playing) {
      await saveCurrentPosition();
      await _player.pause();
      _userPaused = true; // Mark as explicitly paused
    }
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
    } catch (e) {
      debugPrint("Error loading audiobook: $e");
      rethrow;
    }
  }

  // Helper method to save cover art to temporary file
  Future<Uri?> _getCoverArtUri(Uint8List coverArt, String id) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/cover_$id.jpg');
      await file.writeAsBytes(coverArt);
      return Uri.file(file.path);
    } catch (e) {
      debugPrint("Error creating cover art file: $e");
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

    try {
      final chapter = _currentAudiobook!.chapters[index];
      
      // Validate file
      final audioFile = File(chapter.sourcePath);
      if (!await audioFile.exists()) {
        throw Exception("Audio file not found: ${audioFile.path}");
      }
      
      final fileSize = await audioFile.length();
      if (fileSize < 1024) {
        throw Exception("Audio file appears corrupted (too small): ${audioFile.path}");
      }
      debugPrint("Loading chapter: ${chapter.title} from ${audioFile.path}");

      // Prepare artUri
      Uri? artUri;
      try {
        final coverPath = await _storageService.getCachedCoverArtPath(_currentAudiobook!.id);
        if (coverPath != null) {
          artUri = Uri.file(coverPath);
        } else if (_currentAudiobook!.coverArt != null) {
          final sanitizedId = _currentAudiobook!.id.replaceAll(RegExp(r'[^\w]'), '_');
          artUri = await _getCoverArtUri(_currentAudiobook!.coverArt!, sanitizedId);
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
              child: AudioSource.uri(Uri.file(chapter.sourcePath), tag: mediaItem),
              start: chapter.start,
              end: chapter.end,
              tag: mediaItem,
          );
        } else {
          audioSource = AudioSource.uri(Uri.file(chapter.sourcePath), tag: mediaItem);
        }

        // IMPROVEMENT: Robustness fix for EQ muting/state issues.
        final intendedEqEnabled = await _storageService.getEqualizerEnabled(audiobookId: _currentAudiobook!.id);
        final intendedBoost = await _storageService.getVolumeBoost(audiobookId: _currentAudiobook!.id);
        final shouldApplyEffects = intendedEqEnabled || intendedBoost > 0.01;

        // ONLY disable briefly if it's a new book to avoid hardware glitches.
        // For chapter skips in the same book, cycling Enable can cause playback to pause.
        final isNewBook = _lastAppliedBookId != _currentAudiobook!.id;
        if (shouldApplyEffects && isNewBook) {
          debugPrint('📊 New book detected, briefly cycling EQ for hardware reset');
          await _equalizer?.setEnabled(false);
          await _loudnessEnhancer?.setEnabled(false);
        }

        await _player.setAudioSource(audioSource, initialPosition: startPosition);
        
        // Re-enable and restore ALL parameters - Await this to ensure it finishes before we return
        // and potentially call play() from the UI.
        if (shouldApplyEffects) {
          // A small delay is still needed for some Android DSPs to recognize the new session
          await Future.delayed(const Duration(milliseconds: 100));
          
          if (_eqLoadGeneration == currentGeneration) {
            debugPrint('📊 Restoring full EQ state (Chapter Skip)');
            await applyBookEqualizerSettings(force: isNewBook);
          }
        }
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
      
      // OPTIMIZATION: Skip non-essential updates during rapid skips
      if (_eqLoadGeneration != currentGeneration) {
        debugPrint("📊 Load generation $currentGeneration superseded before speed/metadata. Skipping.");
        return;
      }

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
      
      // FINAL CHECK before heavy metadata update
      if (_eqLoadGeneration == currentGeneration) {
        await _updateMediaSessionMetadata(overrideArtUri: artUriString);
        await _updateMediaSessionPlaybackState();
      }
    } catch (e) {
      debugPrint("Error loading chapter $index: $e");
      
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
         artUri = await _storageService.getCachedCoverArtPath(_currentAudiobook!.id);
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
        
        // Safety sync for EQ on play, especially after app relaunch
        if (_lastAppliedBookId != _currentAudiobook?.id) {
          debugPrint('📊 EQ safety sync on play...');
          applyBookEqualizerSettings(force: true);
        }
        
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
    await _player.seek(position);
    debugPrint('Seek to ${position.inMilliseconds} ms');
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
      debugPrint('skipToPrevious: Already at start, restarting chapter');
      await seek(Duration.zero);
    }
    await loadChapter(nextIndex);
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

    if (index >= 0 && index < _currentAudiobook!.chapters.length) {
      await loadChapter(index);
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
    if (_player.duration == null) return;

    final newPosition = _player.position + const Duration(seconds: 15);
    final maxPosition = _player.duration!;

    await seek(
      newPosition > maxPosition ? maxPosition : newPosition,
      propagateToNative: propagateToNative,
    );
    await _updateMediaSessionPlaybackState();
  }

  Future<void> rewind({bool propagateToNative = true}) async {
    final newPosition = _player.position - const Duration(seconds: 15);
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

  Future<void> setBandGain(int bandIndex, double gain) async {
    if (_equalizer == null) return;
    try {
      final parameters = await _equalizer!.parameters;
      final bands = parameters.bands;
      if (bandIndex >= 0 && bandIndex < bands.length) {
        await bands[bandIndex].setGain(gain);
        await _storageService.saveEqualizerBandGain(bandIndex, gain, audiobookId: _currentEqBookId);
      }
    } catch (e) {
      debugPrint('Error setting band gain: $e');
    }
  }

  /// Set generic volume boost (in decibels)
  Future<void> setVolumeBoost(double db) async {
    if (_loudnessEnhancer == null) return;
    
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
    
    await _storageService.saveVolumeBoost(db, audiobookId: _currentEqBookId);
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
    
    // Avoid redundant applications unless forced
    if (!force && _lastAppliedBookId == bookId && !_isApplyingEq) {
      return;
    }

    // Mutex to prevent concurrent EQ applications which can cause muting/crashes
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

      // 1. Prepare Hardware Parameters
      final parameters = await _equalizer!.parameters;
      final bands = parameters.bands;

      // 2. ALWAYS reset all bands to 0.0 first to avoid ghost settings from other sessions/books
      // We do this even if enabled is false, just to be clean.
      for (var i = 0; i < bands.length; i++) {
        await bands[i].setGain(0.0);
      }

      // 3. Apply Saved Band Gains
      if (bandGains.isNotEmpty) {
        for (var i = 0; i < bands.length; i++) {
          if (bandGains.containsKey(i)) {
            final gain = bandGains[i]!;
            // Safety clamp
            await bands[i].setGain(gain.clamp(-15.0, 15.0));
          }
        }
      }

      // 4. Handle Volume Boost (Loudness Enhancer)
      if (_loudnessEnhancer != null) {
        // Apply target gain before enabling to avoid pop/mute
        await _loudnessEnhancer!.setTargetGain(boost.clamp(0.0, 20.0));
        
        if (boost > 0.01 && enabled) {
          await _loudnessEnhancer!.setEnabled(true);
        } else {
          await _loudnessEnhancer!.setEnabled(false);
        }
      }
      
      // 5. SET ENABLED STATE LAST
      // Only toggle if necessary to avoid unintended pauses/glitches
      final currentEqEnabled = await _equalizer!.enabled;
      if (currentEqEnabled != enabled || force) {
        debugPrint('📊 [EQ SYNC] Setting hardware enabled: $enabled');
        await _equalizer!.setEnabled(enabled);
      }
      
      _lastAppliedBookId = bookId;
      debugPrint('📊 [EQ SYNC] ✅ Success for $bookId');
    } catch (e) {
      debugPrint('📊 [EQ SYNC] ❌ Error: $e');
      // On error, let's try to at least disable it to recover audio
      try {
        await _equalizer?.setEnabled(false);
      } catch (_) {}
    } finally {
      _isApplyingEq = false;
    }
  }

}
