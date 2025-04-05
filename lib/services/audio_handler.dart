import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

import '../models/audiobook.dart';
import 'storage_service.dart';

// --- Global Handler Instance Management ---
MyAudioHandler? _audioHandlerInstance;

Future<MyAudioHandler> initAudioService() async {
  if (_audioHandlerInstance != null) {
    debugPrint("initAudioService: Handler already initialized.");
    return _audioHandlerInstance!;
  }
  debugPrint("initAudioService: Initializing NEW Audio Handler instance...");
  _audioHandlerInstance = await AudioService.init<MyAudioHandler>(
    builder: () => MyAudioHandler._internal(),
    config: const AudioServiceConfig(
      androidNotificationChannelId:
          'com.yourapp.audiobook_player.channel.audio', // Replace
      androidNotificationChannelName: 'Audiobook Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  debugPrint("initAudioService: Audio Handler instance assigned globally.");
  return _audioHandlerInstance!;
}

MyAudioHandler getAudioHandlerInstance() {
  if (_audioHandlerInstance == null) {
    throw Exception("CRITICAL: Audio handler has not been initialized...");
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

  // *** FIX: Override the field directly to match BaseAudioHandler ***
  // BaseAudioHandler defines 'queue' as a BehaviorSubject field.
  @override
  final BehaviorSubject<List<MediaItem>> queue =
      BehaviorSubject<List<MediaItem>>.seeded([]);

  // BaseAudioHandler defines 'mediaItem' as a BehaviorSubject field.
  @override
  final BehaviorSubject<MediaItem?> mediaItem =
      BehaviorSubject<MediaItem?>.seeded(null);

  // --- Constructor ---
  MyAudioHandler._internal() {
    debugPrint("MyAudioHandler._internal() constructor START");
    _loadEmptyPlaylist();
    _notifyAudioHandlerAboutPlaybackEvents();
    _listenForDurationChanges();
    _listenForCurrentSongIndexChanges();
    _listenForSequenceStateChanges();
    debugPrint("MyAudioHandler._internal() constructor END");
  }

  // --- Internal Setup ---
  Future<void> _loadEmptyPlaylist() async {
    try {
      await _player.setAudioSource(_playlist);
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
    _currentAudiobookId = audiobook.id;
    final mediaItems = audiobook.chapters.map((c) => c.toMediaItem()).toList();

    // *** FIX: Emit via the overridden queue subject ***
    queue.add(mediaItems);

    final audioSources =
        mediaItems
            .map((item) => AudioSource.uri(Uri.file(item.id), tag: item))
            .toList();
    await _playlist.clear();
    if (audioSources.isNotEmpty) {
      await _playlist.addAll(audioSources);
    } else {
      queue.add([]);
      mediaItem.add(null);
      return;
    } // FIX: Emit via subjects
    int startIndex = 0;
    if (startChapterId != null) {
      startIndex = mediaItems.indexWhere((i) => i.id == startChapterId);
      if (startIndex == -1) startIndex = 0;
    }
    try {
      await _player.setAudioSource(
        _playlist,
        initialIndex: startIndex,
        initialPosition: startPosition ?? Duration.zero,
      );
      final sequence = _player.sequence;
      MediaItem? currentItem =
          (sequence != null &&
                  sequence.isNotEmpty &&
                  startIndex < sequence.length)
              ? sequence[startIndex].tag as MediaItem?
              : null;
      mediaItem.add(currentItem); // FIX: Emit via subject
      if (currentItem != null) {
        _player.durationStream.first.then((d) {
          if (d != null && mediaItem.value?.id == currentItem.id) {
            mediaItem.add(currentItem.copyWith(duration: d));
          }
        }); // FIX: Emit via subject
      }
    } catch (e) {
      mediaItem.add(null);
      queue.add([]);
      debugPrint("Error setting source: $e");
    } // FIX: Emit via subjects
  }

  // This method signature likely needs to change if the queue override changed,
  // but since QueueHandler requires addQueueItems, we keep it.
  // However, it remains effectively unused in this implementation.
  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    debugPrint(
      "addQueueItems called but ignored - use loadPlaylist custom action.",
    );
    // If BaseAudioHandler handles queue directly, this might need implementation
    // or could potentially be removed if not strictly needed by the mixin implementation.
    // For now, keep it as a no-op.
  }

  // --- Event Listening ---
  void _notifyAudioHandlerAboutPlaybackEvents() {
    _player.playbackEventStream.listen(
      (PlaybackEvent event) {
        final playing = _player.playing;
        playbackState.add(
          playbackState.value.copyWith(
            controls: [/* ... controls ... */],
            systemActions: const {/* ... system actions ... */},
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

  AudioProcessingState _mapProcessingState(ProcessingState s) {
    switch (s) {
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
      final ci = mediaItem.value; // Read from subject
      if (duration != null && ci != null && ci.duration != duration) {
        final ui = ci.copyWith(duration: duration);
        final currentQueue = List<MediaItem>.from(
          queue.value,
        ); // Read from subject
        final idx = currentQueue.indexWhere((i) => i.id == ui.id);
        if (idx != -1) {
          currentQueue[idx] = ui;
          queue.add(currentQueue); // Emit via subject
        }
        if (mediaItem.value?.id == ui.id) {
          // Read from subject
          mediaItem.add(ui); // Emit via subject
        }
      }
    });
  }

  void _listenForCurrentSongIndexChanges() {
    _player.currentIndexStream.distinct().listen((index) {
      final currentQueue = queue.value; // Read from subject
      final oldIdx = playbackState.value.queueIndex;
      if (_currentAudiobookId != null &&
          oldIdx != null &&
          oldIdx < currentQueue.length &&
          oldIdx != index) {
        _saveCurrentPosition(
          isFinishing: true,
          specificChapterId: currentQueue[oldIdx].id,
        );
      }
      MediaItem? ni =
          (index != null && index < currentQueue.length)
              ? currentQueue[index]
              : null;
      if (mediaItem.value?.id != ni?.id) {
        // Read from subject
        mediaItem.add(ni); // Emit via subject
      }
    });
  }

  void _listenForSequenceStateChanges() {
    _player.sequenceStateStream.listen((SequenceState? ss) {
      final seq = ss?.sequence;
      final idx = ss?.currentIndex;
      if (seq == null || seq.isEmpty) {
        if (queue.value.isNotEmpty) {
          queue.add([]);
          mediaItem.add(null);
        }
        return;
      } // Read/Emit via subjects
      final items = seq.map((s) => s.tag as MediaItem).toList();
      if (!listEquals(queue.value, items)) {
        queue.add(items);
      } // Read/Emit via subject
      MediaItem? ni = (idx != null && idx < items.length) ? items[idx] : null;
      if (mediaItem.value?.id != ni?.id) {
        mediaItem.add(ni);
      } // Read/Emit via subject
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
    queue.add([]); // Emit via subject
    mediaItem.add(null); // Emit via subject
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
    final qLen = queue.value.length; // Read from subject
    if (index < 0 || index >= qLen) return;
    if (_player.processingState != ProcessingState.completed &&
        index != _player.currentIndex) {
      await _saveCurrentPosition();
    }
    await _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> rewind() async {
    final newPos = _player.position - const Duration(seconds: 15);
    await _player.seek(newPos < Duration.zero ? Duration.zero : newPos);
  }

  @override
  Future<void> fastForward() async {
    final newPos = _player.position + const Duration(seconds: 15);
    final dur = _player.duration;
    await _player.seek(dur != null && newPos > dur ? dur : newPos);
  }

  // --- Custom Actions ---
  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    /* ... same logic ... */
  }

  // --- Position Saving ---
  Future<void> _saveCurrentPosition({
    bool isFinishing = false,
    String? specificChapterId,
  }) async {
    MediaItem? item;
    final q = queue.value; // Read from subject
    if (specificChapterId != null) {
      try {
        item = q.firstWhere((i) => i.id == specificChapterId);
      } catch (e) {
        item = null;
      }
    } else {
      item = mediaItem.value;
    } // Read from subject
    final cid = item?.id;
    final aid = _currentAudiobookId;
    if (aid != null && aid.isNotEmpty && cid != null && cid.isNotEmpty) {
      final pos = _player.position;
      final pSave =
          (isFinishing || pos < const Duration(seconds: 2))
              ? Duration.zero
              : pos;
      try {
        await _storageService.saveLastPosition(aid, cid, pSave);
      } catch (e) {
        /* log */
      }
    }
  }

  // --- Audio Focus Handling ---
  // Use 'dynamic' workaround for 'AudioInterruption' if IDE complains.
  @override
  Future<void> onAudioFocusGained(dynamic interruption) async {
    /* ... same logic using dynamic ... */
  }
  @override
  Future<void> onAudioFocusLost(dynamic interruption) async {
    /* ... same logic using dynamic ... */
  }
  @override
  Future<void> onAudioBecomingNoisy() async {
    /* ... same logic ... */
  }

  // --- Service Lifecycle ---
  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }

  @override
  Future<void> dispose() async {
    await _saveCurrentPosition(isFinishing: true);
    await _player.dispose();
    queue.close(); // Close the subject
    mediaItem.close(); // Close the subject
    _audioHandlerInstance = null;
    await super.stop();
    debugPrint("dispose: Audio Handler Disposed completely.");
  }
}
