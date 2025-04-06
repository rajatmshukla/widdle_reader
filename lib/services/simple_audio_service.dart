import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'dart:async';
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
            // Pause playback
            pause();
          }
        } else {
          // Interruption ended
          if (event.type == AudioInterruptionType.duck) {
            // Restore volume
            _player.setVolume(1.0);
          } else if (_notificationsEnabled) {
            // Resume playback if notifications are enabled
            play();
          }
        }
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

      final currentChapter = _currentAudiobook!.chapters[_currentChapterIndex];

      // Set metadata for media notifications
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.file(currentChapter.id),
          tag: MediaItem(
            id: currentChapter.id,
            album: _currentAudiobook!.title,
            title: currentChapter.title,
            artUri:
                _currentAudiobook!.coverArt != null
                    ? Uri.dataFromBytes(_currentAudiobook!.coverArt!)
                    : null,
            duration: currentChapter.duration,
          ),
        ),
        initialPosition: _player.position,
      );

      _notificationsEnabled = true;
      debugPrint("Media notifications enabled");
    } catch (e) {
      debugPrint("Error enabling notifications: $e");
    }
  }

  // Load an audiobook
  Future<void> loadAudiobook(
    Audiobook audiobook, {
    int startChapter = 0,
    Duration? startPosition,
  }) async {
    try {
      // If we're already playing this audiobook, don't interrupt
      if (_currentAudiobook?.id == audiobook.id && _player.playing) {
        debugPrint("Already playing this audiobook, continuing playback");
        return;
      }

      _currentAudiobook = audiobook;
      _currentChapterIndex = startChapter.clamp(
        0,
        audiobook.chapters.length - 1,
      );

      await loadChapter(_currentChapterIndex, startPosition: startPosition);
      debugPrint("Loaded audiobook: ${audiobook.title}");
    } catch (e) {
      debugPrint("Error loading audiobook: $e");
      rethrow;
    }
  }

  // Load a specific chapter
  Future<void> loadChapter(int index, {Duration? startPosition}) async {
    if (_currentAudiobook == null ||
        index < 0 ||
        index >= _currentAudiobook!.chapters.length) {
      throw Exception("Invalid chapter index");
    }

    try {
      final chapter = _currentAudiobook!.chapters[index];

      if (_notificationsEnabled) {
        // Use the notification-compatible audio source
        await _player.setAudioSource(
          AudioSource.uri(
            Uri.file(chapter.id),
            tag: MediaItem(
              id: chapter.id,
              album: _currentAudiobook!.title,
              title: chapter.title,
              artUri:
                  _currentAudiobook!.coverArt != null
                      ? Uri.dataFromBytes(_currentAudiobook!.coverArt!)
                      : null,
              duration: chapter.duration,
            ),
          ),
        );
      } else {
        // Use the simple file path
        await _player.setFilePath(chapter.id);
      }

      if (startPosition != null) {
        await _player.seek(startPosition);
      }

      _currentChapterIndex = index;
      _currentChapterSubject.add(index);
      debugPrint("Loaded chapter: ${chapter.title}");
    } catch (e) {
      debugPrint("Error loading chapter: $e");
      rethrow;
    }
  }

  // Start the auto-save timer
  void _startAutoSave() {
    // Cancel any existing timer
    _stopAutoSave();

    // Create a new timer that saves position every 30 seconds
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      await _saveCurrentPosition(silent: true);
    });

    debugPrint("Started auto-save timer for playback position");
  }

  // Stop the auto-save timer
  void _stopAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
  }

  // Enhanced position saving
  Future<Map<String, dynamic>> _saveCurrentPosition({
    bool silent = false,
  }) async {
    if (_currentAudiobook == null) {
      return {};
    }

    final position = _player.position;
    final audiobookId = _currentAudiobook!.id;
    final chapterId = _currentAudiobook!.chapters[_currentChapterIndex].id;

    try {
      await _storageService.saveLastPosition(audiobookId, chapterId, position);

      if (!silent) {
        debugPrint("Saved position for $audiobookId: $chapterId at $position");
      }

      return {
        'audiobookId': audiobookId,
        'chapterId': chapterId,
        'position': position,
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

  // Playback controls
  Future<void> play() async {
    await _player.play();
    _startAutoSave();
  }

  Future<void> pause() async {
    await _player.pause();
    _stopAutoSave();
    await _saveCurrentPosition(); // Save immediately on pause
  }

  Future<void> stop() async {
    _stopAutoSave();
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
      await loadChapter(nextIndex);
      await play();
    }
  }

  Future<void> skipToPrevious() async {
    if (_currentAudiobook == null) return;

    final prevIndex = _currentChapterIndex - 1;
    if (prevIndex >= 0) {
      await loadChapter(prevIndex);
      await play();
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
    _stopAutoSave(); // Stop the timer if running
    return await _saveCurrentPosition();
  }

  // Cleanup
  Future<void> dispose() async {
    _stopAutoSave();
    await _saveCurrentPosition(); // Save position one last time
    await _player.dispose();
    await _positionSubject.close();
    await _durationSubject.close();
    await _currentChapterSubject.close();
    await _playingSubject.close();
    await _speedSubject.close();
  }
}
