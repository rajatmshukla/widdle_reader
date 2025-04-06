import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

import '../models/audiobook.dart';
import 'storage_service.dart';

// --- Global Handler Instance Management ---
MyAudioHandler? _audioHandlerInstance;

bool _isAudioHandlerInitializing = false;

Future<MyAudioHandler> initAudioService() async {
  if (_audioHandlerInstance != null) {
    debugPrint("initAudioService: Handler already initialized.");
    return _audioHandlerInstance!;
  }

  // Add safety to prevent multiple simultaneous initializations
  if (_isAudioHandlerInitializing) {
    debugPrint(
      "initAudioService: Initialization already in progress. Waiting...",
    );
    // Wait for initialization to complete
    for (int i = 0; i < 50; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (_audioHandlerInstance != null) {
        return _audioHandlerInstance!;
      }
    }
    throw Exception("Timeout waiting for audio handler initialization");
  }

  _isAudioHandlerInitializing = true;

  try {
    debugPrint("initAudioService: Initializing NEW Audio Handler instance...");
    _audioHandlerInstance = await AudioService.init<MyAudioHandler>(
      builder: () => MyAudioHandler._internal(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.widdle_reader.channel.audio',
        androidNotificationChannelName: 'Audiobook Playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
    debugPrint("initAudioService: Audio Handler instance assigned globally.");
    return _audioHandlerInstance!;
  } catch (e, stackTrace) {
    debugPrint("CRITICAL ERROR initializing AudioService: $e");
    debugPrint("$stackTrace");
    _isAudioHandlerInitializing = false;
    rethrow;
  } finally {
    _isAudioHandlerInitializing = false;
  }
}

MyAudioHandler getAudioHandlerInstance() {
  if (_audioHandlerInstance == null) {
    throw Exception(
      "CRITICAL: Audio handler has not been initialized yet. Call initAudioService() first.",
    );
  }
  debugPrint("getAudioHandlerInstance: Returning valid instance.");
  return _audioHandlerInstance!;
}

// --- MyAudioHandler Implementation ---
class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _player = AudioPlayer();
  final _playlist = ConcatenatingAudioSource(children: []);
  final _storageService = StorageService();
  String? _currentAudiobookId;

  // --- Stream Controllers & Overrides ---
  // Override the field directly to match BaseAudioHandler
  @override
  final BehaviorSubject<List<MediaItem>> queue =
      BehaviorSubject<List<MediaItem>>.seeded([]);

  // BaseAudioHandler defines 'mediaItem' as a BehaviorSubject field
  @override
  final BehaviorSubject<MediaItem?> mediaItem =
      BehaviorSubject<MediaItem?>.seeded(null);

  // --- Constructor ---
  MyAudioHandler._internal() {
    debugPrint("MyAudioHandler._internal() constructor START");
    _initializePlayer();
    debugPrint("MyAudioHandler._internal() constructor END");
  }

  // --- Internal Setup ---
  Future<void> _initializePlayer() async {
    try {
      // Set up empty playlist
      await _loadEmptyPlaylist();

      // Set up event listeners
      _notifyAudioHandlerAboutPlaybackEvents();
      _listenForDurationChanges();
      _listenForCurrentSongIndexChanges();
      _listenForSequenceStateChanges();

      debugPrint("Player successfully initialized");
    } catch (e, stackTrace) {
      debugPrint("Error initializing player: $e");
      debugPrint("$stackTrace");
      // Don't rethrow - we want to at least create the handler
    }
  }

  Future<void> _loadEmptyPlaylist() async {
    try {
      await _player.setAudioSource(_playlist);
      debugPrint("Empty playlist loaded successfully");
    } catch (e) {
      debugPrint(
        "_loadEmptyPlaylist: Error setting initial empty playlist: $e",
      );
    }
  }

  // --- Playlist Management ---
  Future<void> loadPlaylist(
    Audiobook audiobook, {
    String? startChapterId,
    Duration? startPosition,
  }) async {
    debugPrint(
      "loadPlaylist: Loading audiobook '${audiobook.title}' with ${audiobook.chapters.length} chapters",
    );

    _currentAudiobookId = audiobook.id;
    final mediaItems = audiobook.chapters.map((c) => c.toMediaItem()).toList();

    // Add items to queue subject
    queue.add(mediaItems);
    debugPrint("Queue updated with ${mediaItems.length} items");

    final audioSources =
        mediaItems
            .map((item) => AudioSource.uri(Uri.file(item.id), tag: item))
            .toList();

    try {
      await _playlist.clear();
      debugPrint("Playlist cleared");

      if (audioSources.isNotEmpty) {
        await _playlist.addAll(audioSources);
        debugPrint("Added ${audioSources.length} sources to playlist");
      } else {
        debugPrint("No audio sources to add");
        queue.add([]);
        mediaItem.add(null);
        return;
      }

      // Find start index
      int startIndex = 0;
      if (startChapterId != null) {
        debugPrint("Looking for start chapter ID: $startChapterId");
        startIndex = mediaItems.indexWhere((i) => i.id == startChapterId);
        if (startIndex == -1) {
          debugPrint("Start chapter ID not found, defaulting to index 0");
          startIndex = 0;
        } else {
          debugPrint("Found start chapter at index $startIndex");
        }
      }

      // Set the audio source
      debugPrint("Setting audio source with initial index $startIndex");
      await _player.setAudioSource(
        _playlist,
        initialIndex: startIndex,
        initialPosition: startPosition ?? Duration.zero,
      );

      // Update current media item
      final sequence = _player.sequence;
      MediaItem? currentItem =
          (sequence != null &&
                  sequence.isNotEmpty &&
                  startIndex < sequence.length)
              ? sequence[startIndex].tag as MediaItem?
              : null;

      mediaItem.add(currentItem);
      debugPrint("Current media item set to: ${currentItem?.title ?? 'null'}");

      // Update duration if available
      if (currentItem != null) {
        _player.durationStream.first.then((d) {
          if (d != null && mediaItem.value?.id == currentItem.id) {
            mediaItem.add(currentItem.copyWith(duration: d));
            debugPrint("Updated duration for current item: $d");
          }
        });
      }
    } catch (e, stackTrace) {
      debugPrint("ERROR in loadPlaylist: $e");
      debugPrint("$stackTrace");
      mediaItem.add(null);
      queue.add([]);
    }
  }

  // QueueHandler requires this method, keep it even if unused
  @override
  Future<void> addQueueItems(List<MediaItem> items) async {
    debugPrint(
      "addQueueItems called but ignored - use loadPlaylist custom action instead",
    );
  }

  // --- Event Listening ---
  void _notifyAudioHandlerAboutPlaybackEvents() {
    _player.playbackEventStream.listen(
      (PlaybackEvent event) {
        final playing = _player.playing;
        playbackState.add(
          playbackState.value.copyWith(
            controls: [
              MediaControl.skipToPrevious,
              if (playing) MediaControl.pause else MediaControl.play,
              MediaControl.skipToNext,
            ],
            systemActions: const {
              MediaAction.seek,
              MediaAction.seekForward,
              MediaAction.seekBackward,
            },
            androidCompactActionIndices: const [0, 1, 3],
            processingState: _mapProcessingState(_player.processingState),
            playing: playing,
            updatePosition: _player.position,
            bufferedPosition: _player.bufferedPosition,
            speed: _player.speed,
            queueIndex: event.currentIndex,
          ),
        );
      },
      onError: (Object e, StackTrace s) {
        debugPrint('ERROR in playback stream: $e\n$s');
      },
    );
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  void _listenForDurationChanges() {
    _player.durationStream.distinct().listen((duration) {
      final currentItem = mediaItem.value;
      if (duration != null &&
          currentItem != null &&
          currentItem.duration != duration) {
        final updatedItem = currentItem.copyWith(duration: duration);

        // Update the item in the queue as well
        final currentQueue = List<MediaItem>.from(queue.value);
        final idx = currentQueue.indexWhere((i) => i.id == updatedItem.id);
        if (idx != -1) {
          currentQueue[idx] = updatedItem;
          queue.add(currentQueue);
        }

        // Update current item if it's the same ID
        if (mediaItem.value?.id == updatedItem.id) {
          mediaItem.add(updatedItem);
        }
      }
    });
  }

  void _listenForCurrentSongIndexChanges() {
    _player.currentIndexStream.distinct().listen((index) {
      final currentQueue = queue.value;
      final oldIdx = playbackState.value.queueIndex;

      // Save position when changing tracks (if not at end of playlist)
      if (_currentAudiobookId != null &&
          oldIdx != null &&
          oldIdx < currentQueue.length &&
          oldIdx != index) {
        _saveCurrentPosition(
          isFinishing: true,
          specificChapterId: currentQueue[oldIdx].id,
        );
      }

      // Update current media item
      MediaItem? newItem =
          (index != null && index < currentQueue.length)
              ? currentQueue[index]
              : null;

      if (mediaItem.value?.id != newItem?.id) {
        mediaItem.add(newItem);
      }
    });
  }

  void _listenForSequenceStateChanges() {
    _player.sequenceStateStream.listen((SequenceState? state) {
      final sequence = state?.sequence;
      final index = state?.currentIndex;

      if (sequence == null || sequence.isEmpty) {
        if (queue.value.isNotEmpty) {
          queue.add([]);
          mediaItem.add(null);
        }
        return;
      }

      // Update queue
      final items = sequence.map((s) => s.tag as MediaItem).toList();
      if (!listEquals(queue.value, items)) {
        queue.add(items);
      }

      // Update current item
      MediaItem? newItem =
          (index != null && index < items.length) ? items[index] : null;

      if (mediaItem.value?.id != newItem?.id) {
        mediaItem.add(newItem);
      }
    });
  }

  // --- Playback Control Overrides ---
  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _saveCurrentPosition(isFinishing: true);
    await _player.stop();
    _currentAudiobookId = null;
    await _playlist.clear();
    queue.add([]);
    mediaItem.add(null);
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        queueIndex: null,
      ),
    );
    await super.stop();
  }

  // --- Standard Action Overrides ---
  @override
  Future<void> skipToNext() async {
    if (_player.processingState != ProcessingState.completed) {
      await _saveCurrentPosition();
    }
    await _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await _saveCurrentPosition();
    await _player.seekToPrevious();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    final queueLength = queue.value.length;
    if (index < 0 || index >= queueLength) return;

    if (_player.processingState != ProcessingState.completed &&
        index != _player.currentIndex) {
      await _saveCurrentPosition();
    }

    await _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> rewind() async {
    final newPosition = _player.position - const Duration(seconds: 30);
    await _player.seek(
      newPosition < Duration.zero ? Duration.zero : newPosition,
    );
  }

  @override
  Future<void> fastForward() async {
    final newPosition = _player.position + const Duration(seconds: 30);
    final duration = _player.duration;
    await _player.seek(
      duration != null && newPosition > duration ? duration : newPosition,
    );
  }

  // --- Custom Actions ---
  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    debugPrint("Custom action received: $name");

    switch (name) {
      case 'loadPlaylist':
        if (extras != null) {
          final audiobook = extras['audiobook'] as Audiobook?;
          final startChapterId = extras['startChapterId'] as String?;
          final startPosition = extras['startPosition'] as Duration?;

          if (audiobook != null) {
            debugPrint("Loading playlist for audiobook: ${audiobook.title}");
            await loadPlaylist(
              audiobook,
              startChapterId: startChapterId,
              startPosition: startPosition,
            );
            return true;
          } else {
            debugPrint("No audiobook provided in loadPlaylist extras");
          }
        }
        return false;

      case 'savePosition':
        final isFinishing = extras?['isFinishing'] == true;
        debugPrint("Saving position (isFinishing=$isFinishing)");
        await _saveCurrentPosition(isFinishing: isFinishing);
        return true;

      default:
        debugPrint("Unknown custom action: $name");
        return false;
    }
  }

  // --- Position Saving ---
  Future<void> _saveCurrentPosition({
    bool isFinishing = false,
    String? specificChapterId,
  }) async {
    MediaItem? item;
    final currentQueue = queue.value;

    // Determine which chapter ID to use
    if (specificChapterId != null) {
      try {
        item = currentQueue.firstWhere((i) => i.id == specificChapterId);
        debugPrint("Using specific chapter ID: $specificChapterId");
      } catch (e) {
        debugPrint("Specific chapter ID not found: $specificChapterId");
        item = null;
      }
    } else {
      item = mediaItem.value;
      debugPrint("Using current media item: ${item?.title ?? 'null'}");
    }

    final chapterId = item?.id;
    final audiobookId = _currentAudiobookId;

    if (audiobookId != null &&
        audiobookId.isNotEmpty &&
        chapterId != null &&
        chapterId.isNotEmpty) {
      final position = _player.position;

      // Reset position if finishing or at the start
      final positionToSave =
          (isFinishing || position < const Duration(seconds: 2))
              ? Duration.zero
              : position;

      try {
        debugPrint(
          "Saving position for audiobook $audiobookId, chapter $chapterId: $positionToSave",
        );
        await _storageService.saveLastPosition(
          audiobookId,
          chapterId,
          positionToSave,
        );
      } catch (e) {
        debugPrint("Error saving position: $e");
      }
    } else {
      debugPrint("Not saving position - missing audiobookId or chapterId");
    }
  }

  // --- Audio Focus Handling ---
  @override
  Future<void> onAudioFocusGained(dynamic interruption) async {
    debugPrint("Audio focus gained");
    // Resume playback if it was playing before
    if (playbackState.value.playing) {
      await play();
    }
  }

  @override
  Future<void> onAudioFocusLost(dynamic interruption) async {
    debugPrint("Audio focus lost");
    // Pause when focus is lost
    await pause();
  }

  @override
  Future<void> onAudioBecomingNoisy() async {
    debugPrint("Audio becoming noisy (e.g., headphones unplugged)");
    // Pause when headphones disconnected
    await pause();
  }

  // --- Service Lifecycle ---
  @override
  Future<void> onTaskRemoved() async {
    debugPrint("Task removed - stopping service");
    await stop();
  }

  @override
  Future<void> dispose() async {
    debugPrint("Disposing audio handler");
    await _saveCurrentPosition(isFinishing: true);
    await _player.dispose();
    queue.close();
    mediaItem.close();
    _audioHandlerInstance = null;
    await super.stop();
    debugPrint("Audio Handler Disposed completely");
  }
}
