import 'package:flutter/foundation.dart';
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

class SimpleAudioService {
  // Singleton instance
  static final SimpleAudioService _instance = SimpleAudioService._internal();
  factory SimpleAudioService() => _instance;

  // Method channel for Android Auto MediaSession updates
  static const _audioBridgeChannel = MethodChannel('com.widdlereader.app/audio_bridge');

  // Internal player
  final AudioPlayer _player = AudioPlayer();

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

  // Timer for auto-saving
  Timer? _autoSaveTimer;
  final StorageService _storageService = StorageService();

  // Timer for MediaSession updates
  Timer? _mediaSessionUpdateTimer;

  // Add this flag to track user intent
  bool _userPaused = false;

  // Stream getters
  Stream<Duration> get positionStream => _positionSubject.stream;
  Stream<Duration> get durationStream => _durationSubject.stream;
  Stream<int> get currentChapterStream => _currentChapterSubject.stream;
  Stream<bool> get playingStream => _playingSubject.stream;
  Stream<double> get speedStream => _speedSubject.stream;

  // Current state getters
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  bool get isPlaying => _player.playing;
  int get currentChapterIndex => _currentChapterIndex;
  Audiobook? get currentAudiobook => _currentAudiobook;
  double get speed => _player.speed;

  // Private constructor
  SimpleAudioService._internal() {
    _initStreams();
    _initAudioSession();
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

    // Playing state updates
    _player.playingStream.listen((playing) {
      _playingSubject.add(playing);
      if (playing) {
        _startMediaSessionUpdates();
      } else {
        _stopMediaSessionUpdates();
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
      _audioSession!.interruptionEventStream.listen((event) {
        if (event.begin) {
          // Audio interrupted - pause playback
          if (event.type == AudioInterruptionType.duck) {
            // Lower volume temporarily
            _player.setVolume(0.5);
          } else {
            // Store current state before pausing
            bool wasPlaying = _player.playing;
            // Pause playback
            pause();
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
    // If something is already playing, save state and pause
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

  // Load a chapter by index
  Future<void> loadChapter(int index, {Duration? startPosition}) async {
    if (_currentAudiobook == null ||
        index < 0 ||
        index >= _currentAudiobook!.chapters.length) {
      throw Exception("Invalid chapter index: $index");
    }

    try {
      final chapter = _currentAudiobook!.chapters[index];
      final audioFilePath = chapter.sourcePath;
      
      // CRITICAL FIX: Validate audio file exists and is accessible
      final audioFile = File(audioFilePath);
      if (!await audioFile.exists()) {
        throw Exception("Audio file not found: ${audioFile.path}");
      }
      
      // Check file size to ensure it's not corrupted
      final fileSize = await audioFile.length();
      if (fileSize < 1024) { // Less than 1KB is likely corrupted
        throw Exception("Audio file appears corrupted (too small): ${audioFile.path}");
      }
      
      debugPrint("Loading chapter: ${chapter.title} from ${audioFile.path} (${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB)");

      // Prepare artUri from cover art if available
      Uri? artUri;
      if (_currentAudiobook!.coverArt != null) {
        try {
          // Create a temporary file for cover art for better notification support
          final sanitizedId = _currentAudiobook!.id.replaceAll(RegExp(r'[^\w]'), '_');
          artUri = await _getCoverArtUri(_currentAudiobook!.coverArt!, sanitizedId);
          debugPrint("Cover art URI created: $artUri");
        } catch (e) {
          debugPrint("Error creating artUri: $e");
        }
      }
      
      // Create a MediaItem for the chapter - ALWAYS create this for just_audio_background
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
        // Add extra metadata to enhance the notification display
        extras: {
          'audiobookId': _currentAudiobook!.id,
          'chapterIndex': index,
          'totalChapters': _currentAudiobook!.chapters.length,
          'bookTitle': _currentAudiobook!.title,
          'hasPrevious': index > 0,
          'hasNext': index < _currentAudiobook!.chapters.length - 1,
        },
      );

      // CRITICAL FIX: Better error handling for audio source loading
      try {
        debugPrint("Setting audio source for: ${audioFile.path}");
        
        AudioSource audioSource;
        
        // Check if this is a segment (embedded chapter) or a full file
        if (chapter.end != null && chapter.end! > Duration.zero && chapter.end! > chapter.start) {
          debugPrint("Loading chapter segment: ${chapter.start} to ${chapter.end}");
          audioSource = ClippingAudioSource(
            child: AudioSource.uri(
              Uri.file(chapter.sourcePath),
              tag: mediaItem,
            ),
            start: chapter.start,
            end: chapter.end,
            tag: mediaItem,
          );
        } else {
          debugPrint("Loading full file chapter");
          audioSource = AudioSource.uri(
            Uri.file(chapter.sourcePath),
            tag: mediaItem,
          );
        }

        await _player.setAudioSource(
          audioSource,
          initialPosition: startPosition,
        );
        debugPrint("Audio source set successfully");
      } catch (audioSourceError) {
        // More specific error handling for common audio issues
        if (audioSourceError.toString().contains('FileSystemException')) {
          throw Exception("Cannot access audio file. Check file permissions: ${audioFile.path}");
        } else if (audioSourceError.toString().contains('FormatException') || 
                   audioSourceError.toString().contains('Unsupported')) {
          throw Exception("Unsupported audio format or corrupted file: ${audioFile.path}");
        } else if (audioSourceError.toString().contains('NetworkException')) {
          throw Exception("File access error (may be on unavailable drive): ${audioFile.path}");
        } else {
          throw Exception("Failed to load audio file: $audioSourceError");
        }
      }

      _currentChapterIndex = index;
      _currentChapterSubject.add(index);
      debugPrint("Successfully loaded chapter: ${chapter.title}");
      await _updateMediaSessionMetadata();
      await _updateMediaSessionPlaybackState();
    } catch (e) {
      debugPrint("Error loading chapter $index: $e");
      
      // Provide user-friendly error message
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
    
    // Create a new timer that saves position every 30 seconds
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_currentAudiobook != null && isPlaying) {
        debugPrint("Auto-saving playback position");
        saveCurrentPosition();
      }
    });
  }

  // Update MediaSession metadata (call when chapter loads)
  Future<void> _updateMediaSessionMetadata() async {
    if (_currentAudiobook == null) return;
    
    try {
      final chapter = _currentAudiobook!.chapters[_currentChapterIndex];
      final duration = chapter.duration ?? _player.duration ?? Duration.zero;
      
      // Get cover art URI if available
      String? artUri;
      if (_currentAudiobook!.coverArt != null) {
        final tempDir = await getTemporaryDirectory();
        final sanitizedId = _currentAudiobook!.id.replaceAll(RegExp(r'[\W]'), '_');
        final coverFile = File('${tempDir.path}/cover_$sanitizedId.jpg');
        if (await coverFile.exists()) {
          artUri = coverFile.path;
        }
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
      
      debugPrint("Updated Android Auto metadata: ${chapter.title}");
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
        _notifyPlaybackChanged(nativeUpdate: true);
        if (propagateToNative) {
          _invokeMediaSessionCommand('play');
        }
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
    _notifyPlaybackChanged(nativeUpdate: true);
    if (propagateToNative) {
      _invokeMediaSessionCommand('pause');
    }
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
    if (propagateToNative) {
      _invokeMediaSessionCommand('seekTo', {
        'position': position.inMilliseconds,
      });
    }
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

    await loadChapter(nextIndex);
    _notifyPlaybackChanged(nativeUpdate: true);
    if (propagateToNative) {
      _invokeMediaSessionCommand('skipToNext');
    }
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
    if (propagateToNative) {
      _invokeMediaSessionCommand('seekTo', {
        'position': _player.position.inMilliseconds,
      });
    }
  }

  Future<void> rewind({bool propagateToNative = true}) async {
    final newPosition = _player.position - const Duration(seconds: 15);
    await seek(
      newPosition < Duration.zero ? Duration.zero : newPosition,
      propagateToNative: propagateToNative,
    );
    await _updateMediaSessionPlaybackState();
    if (propagateToNative) {
      _invokeMediaSessionCommand('seekTo', {
        'position': _player.position.inMilliseconds,
      });
    }
  }

  // Save the current position for later resuming
  Future<Map<String, dynamic>> saveCurrentPosition() async {
    _autoSaveTimer?.cancel();
    await _updateMediaSessionPlaybackState();
    return await _saveCurrentPosition();
  }

  // Cleanup
  Future<void> dispose() async {
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
}
