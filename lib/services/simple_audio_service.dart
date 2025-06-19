import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:audio_session/audio_session.dart';
// Add this import:
import 'package:just_audio_background/just_audio_background.dart';
import '../models/audiobook.dart';
import '../services/storage_service.dart';

class SimpleAudioService {
  // Singleton instance
  static final SimpleAudioService _instance = SimpleAudioService._internal();
  factory SimpleAudioService() => _instance;

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
    });

    // Speed updates
    _player.speedStream.listen((speed) {
      _speedSubject.add(speed);
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

      await loadChapter(_currentChapterIndex, startPosition: startPosition);
      debugPrint("Loaded audiobook: ${audiobook.title}");

      // Only auto-play if explicitly requested
      if (autoPlay) {
        await play();
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
      final audioFilePath = chapter.id;
      
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
        await _player.setAudioSource(
          AudioSource.uri(
            Uri.file(audioFile.path),
            tag: mediaItem,
          ),
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
    // Ensure speed is within acceptable range
    final normalizedSpeed = speed.clamp(0.5, 2.0);
    await _player.setSpeed(normalizedSpeed);
    _speedSubject.add(normalizedSpeed);
    debugPrint("Playback speed set to: $normalizedSpeed");
  }

  // Playback controls with user intent tracking
  Future<void> play() async {
    _userPaused = false; // User explicitly requested play
    
    // Always enable notifications when playing
    if (!_notificationsEnabled) {
      await enableNotifications();
    }
    
    await _player.play();
    _startAutoSaveTimer();
  }

  Future<void> pause() async {
    _userPaused = true; // User explicitly requested pause
    await _player.pause();
    _autoSaveTimer?.cancel();
    await _saveCurrentPosition(); // Save immediately on pause
  }

  Future<void> stop() async {
    _autoSaveTimer?.cancel();
    await _saveCurrentPosition();
    await _player.stop();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  // Chapter navigation
  Future<void> skipToNext() async {
    if (_currentAudiobook == null) return;

    final nextIndex = _currentChapterIndex + 1;
    if (nextIndex < _currentAudiobook!.chapters.length) {
      // Save current position before changing chapters
      await _saveCurrentPosition(isFinishing: true);
      
      // Load next chapter and play it
      debugPrint("Skipping to next chapter: $nextIndex");
      await loadChapter(nextIndex);
      
      // Ensure notifications are enabled when using media controls
      if (!_notificationsEnabled) {
        _notificationsEnabled = true;
      }
      
      // Auto-play when skipping chapters via notification controls
      await play();
    } else {
      debugPrint("Already at last chapter, cannot skip to next");
    }
  }

  Future<void> skipToPrevious() async {
    if (_currentAudiobook == null) return;

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
      await play();
    } else {
      debugPrint("Already at first chapter, cannot skip to previous");
    }
  }

  Future<void> skipToChapter(int index) async {
    if (_currentAudiobook == null) return;

    if (index >= 0 && index < _currentAudiobook!.chapters.length) {
      await loadChapter(index);
      await play();
    }
  }

  // Time skipping
  Future<void> fastForward() async {
    if (_player.duration == null) return;

    final newPosition = _player.position + const Duration(seconds: 30);
    final maxPosition = _player.duration!;

    await seek(newPosition > maxPosition ? maxPosition : newPosition);
  }

  Future<void> rewind() async {
    final newPosition = _player.position - const Duration(seconds: 30);
    await seek(newPosition < Duration.zero ? Duration.zero : newPosition);
  }

  // Save the current position for later resuming
  Future<Map<String, dynamic>> saveCurrentPosition() async {
    _autoSaveTimer?.cancel();
    return await _saveCurrentPosition();
  }

  // Cleanup
  Future<void> dispose() async {
    _autoSaveTimer?.cancel();
    await _saveCurrentPosition(); // Save position one last time
    await _player.dispose();
    await _positionSubject.close();
    await _durationSubject.close();
    await _currentChapterSubject.close();
    await _playingSubject.close();
    await _speedSubject.close();
  }
}
