// lib/services/simple_audio_service.dart
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import '../models/audiobook.dart';

class SimpleAudioService {
  // Singleton instance
  static final SimpleAudioService _instance = SimpleAudioService._internal();
  factory SimpleAudioService() => _instance;

  // Internal player
  final AudioPlayer _player = AudioPlayer();

  // Current audiobook info
  Audiobook? _currentAudiobook;
  int _currentChapterIndex = 0;

  // Stream controllers
  final _positionSubject = BehaviorSubject<Duration>.seeded(Duration.zero);
  final _durationSubject = BehaviorSubject<Duration>.seeded(Duration.zero);
  final _currentChapterSubject = BehaviorSubject<int>.seeded(0);
  final _playingSubject = BehaviorSubject<bool>.seeded(false);
  final _speedSubject = BehaviorSubject<double>.seeded(1.0);

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

    // Completion listener - go to next chapter
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        skipToNext();
      }
    });
  }

  // Load an audiobook
  Future<void> loadAudiobook(
    Audiobook audiobook, {
    int startChapter = 0,
    Duration? startPosition,
  }) async {
    try {
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
      await _player.setFilePath(chapter.id);

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

  // Playback controls
  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> stop() => _player.stop();
  Future<void> seek(Duration position) => _player.seek(position);

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

  // Add a method to set playback speed
  Future<void> setSpeed(double speed) async {
    // Ensure speed is within acceptable range
    final normalizedSpeed = speed.clamp(0.5, 2.0);
    await _player.setSpeed(normalizedSpeed);
    _speedSubject.add(normalizedSpeed);
    debugPrint("Playback speed set to: $normalizedSpeed");
  }

  // Time skipping
  Future<void> fastForward() async {
    if (_player.duration == null) return;

    final newPosition = _player.position + const Duration(seconds: 15);
    final maxPosition = _player.duration!;

    await seek(newPosition > maxPosition ? maxPosition : newPosition);
  }

  Future<void> rewind() async {
    final newPosition = _player.position - const Duration(seconds: 15);
    await seek(newPosition < Duration.zero ? Duration.zero : newPosition);
  }

  // Save the current position for later resuming
  Future<Map<String, dynamic>> saveCurrentPosition() async {
    if (_currentAudiobook == null) {
      return {};
    }

    return {
      'audiobookId': _currentAudiobook!.id,
      'chapterId': _currentAudiobook!.chapters[_currentChapterIndex].id,
      'position': _player.position,
    };
  }

  // Cleanup
  Future<void> dispose() async {
    await _player.dispose();
    await _positionSubject.close();
    await _durationSubject.close();
    await _currentChapterSubject.close();
    await _playingSubject.close();
    await _speedSubject.close(); // Add this line
  }
}
