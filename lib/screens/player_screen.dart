import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'dart:async';

// Import local models, handler, widgets, and helpers
import '../models/audiobook.dart';
import '../services/audio_handler.dart';
import 'player_controls.dart';
import '../widgets/seekbar.dart';
import '../utils/helpers.dart';

// Flag to track if initialization is in progress (to prevent multiple simultaneous attempts)
bool _initializingAudioHandler = false;

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  // Handler instance, nullable until initialized
  MyAudioHandler? _audioHandler;
  // Current audiobook data
  Audiobook? _audiobook;
  // State flags
  bool _isLoading = true;
  bool _isHandlerInitialized = false;
  String? _errorMessage;
  bool _canRetry = true;

  /// Combined stream for Seekbar UI updates.
  Stream<PositionData> get _positionDataStream {
    if (!_isHandlerInitialized || _audioHandler == null) {
      return Stream.value(
        PositionData(Duration.zero, Duration.zero, Duration.zero),
      );
    }
    return Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
      AudioService.position,
      _audioHandler!.playbackState
          .map((state) => state.bufferedPosition)
          .distinct(),
      _audioHandler!.mediaItem.map((item) => item?.duration).distinct(),
      (position, bufferedPosition, duration) =>
          PositionData(position, bufferedPosition, duration ?? Duration.zero),
    );
  }

  @override
  void initState() {
    super.initState();
    debugPrint("PlayerScreen: initState START");
    WidgetsBinding.instance.addObserver(this);

    // Use a post-frame callback to ensure the context is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeHandlerAndLoadData();
    });

    debugPrint(
      "PlayerScreen: initState END (scheduled _initializeHandlerAndLoadData)",
    );
  }

  /// Safely initialize the audio handler
  Future<bool> _safelyInitializeAudioHandler() async {
    try {
      // If handler is already initialized globally, just use it
      try {
        _audioHandler = getAudioHandlerInstance();
        debugPrint(
          "PlayerScreen: Successfully obtained existing audio handler instance",
        );
        return true;
      } catch (e) {
        debugPrint(
          "PlayerScreen: No existing handler available, will initialize a new one",
        );
      }

      // If an initialization is already in progress, wait for it
      if (_initializingAudioHandler) {
        debugPrint(
          "PlayerScreen: Audio handler initialization already in progress, waiting...",
        );
        int attempts = 0;
        const maxAttempts = 50; // 5 seconds with 100ms delay

        while (_initializingAudioHandler && attempts < maxAttempts) {
          await Future.delayed(const Duration(milliseconds: 100));
          attempts++;

          // Try to get the handler
          try {
            _audioHandler = getAudioHandlerInstance();
            debugPrint(
              "PlayerScreen: Successfully obtained audio handler after waiting",
            );
            return true;
          } catch (e) {
            // Continue waiting
          }
        }

        if (attempts >= maxAttempts) {
          throw Exception("Timeout waiting for audio handler initialization");
        }
      }

      // Start a new initialization
      _initializingAudioHandler = true;
      try {
        debugPrint("PlayerScreen: Starting audio handler initialization");
        await initAudioService();
        _audioHandler = getAudioHandlerInstance();
        debugPrint("PlayerScreen: Successfully initialized new audio handler");
        return true;
      } finally {
        _initializingAudioHandler = false;
      }
    } catch (e, stackTrace) {
      debugPrint("PlayerScreen: Error initializing audio handler: $e");
      debugPrint("$stackTrace");
      return false;
    }
  }

  /// Initializes the audio handler reference and loads initial audiobook data.
  Future<void> _initializeHandlerAndLoadData() async {
    debugPrint("PlayerScreen: _initializeHandlerAndLoadData START");

    if (_isHandlerInitialized) {
      debugPrint("PlayerScreen: Handler already initialized. Exiting.");
      return;
    }

    try {
      // Add a small delay to ensure context is fully ready
      await Future.delayed(const Duration(milliseconds: 100));

      // Check if still mounted after delay
      if (!mounted) {
        debugPrint("PlayerScreen: Widget no longer mounted after delay");
        return;
      }

      // Try to initialize the audio handler
      final bool success = await _safelyInitializeAudioHandler();
      if (!success) {
        throw Exception("Failed to initialize audio handler");
      }

      _isHandlerInitialized = true;

      // Get route arguments
      if (!mounted) {
        debugPrint(
          "PlayerScreen: Widget no longer mounted after initializing handler",
        );
        return;
      }

      final args = ModalRoute.of(context)?.settings.arguments;
      debugPrint("PlayerScreen: Route arguments received: $args");

      if (args != null && args is Map<String, dynamic>) {
        _audiobook = args['audiobook'] as Audiobook?;
        final startChapterId = args['startChapterId'] as String?;
        final startPosition = args['startPosition'] as Duration?;

        if (_audiobook == null) {
          throw Exception("Audiobook data missing in arguments.");
        }

        debugPrint(
          "PlayerScreen: Parsed arguments - Audiobook: ${_audiobook!.title}, StartChapter: $startChapterId, StartPos: $startPosition",
        );

        // Load the playlist into the handler
        debugPrint("PlayerScreen: Calling _loadAudiobookIntoHandler...");
        await _loadAudiobookIntoHandler(
          _audiobook!,
          startChapterId,
          startPosition,
        );
        debugPrint("PlayerScreen: _loadAudiobookIntoHandler finished.");
      } else {
        throw Exception("Audiobook arguments not received or invalid type.");
      }

      // Update UI state to reflect loading finished
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = null;
        });
        debugPrint("PlayerScreen: Loading complete.");
      }
    } catch (e, stackTrace) {
      debugPrint("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
      debugPrint(
        "PlayerScreen: ERROR during _initializeHandlerAndLoadData: $e",
      );
      debugPrint("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
      debugPrint("$stackTrace");

      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Failed to initialize player: ${e.toString()}";
        });
      }
    }

    debugPrint("PlayerScreen: _initializeHandlerAndLoadData END");
  }

  /// Sends the 'loadPlaylist' custom action to the audio handler.
  Future<void> _loadAudiobookIntoHandler(
    Audiobook book,
    String? startChapterId,
    Duration? startPosition,
  ) async {
    assert(
      _audioHandler != null,
      "Handler cannot be null when loading playlist",
    );

    debugPrint(
      "PlayerScreen: Sending 'loadPlaylist' custom action to handler...",
    );
    try {
      await _audioHandler!.customAction('loadPlaylist', {
        'audiobook': book,
        'startChapterId': startChapterId,
        'startPosition': startPosition,
      });
      debugPrint("PlayerScreen: 'loadPlaylist' action sent successfully.");
    } catch (e, stackTrace) {
      debugPrint("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
      debugPrint(
        "PlayerScreen: Error sending 'loadPlaylist' custom action: $e",
      );
      debugPrint("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
      debugPrint("$stackTrace");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error starting playback.")),
        );
      }
      rethrow;
    }
  }

  void _retryInitialization() {
    if (!_canRetry) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _canRetry = false; // Prevent multiple rapid retries
    });

    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _canRetry = true;
        });
      }
    });

    _initializeHandlerAndLoadData();
  }

  @override
  void dispose() {
    debugPrint("PlayerScreen: dispose called.");
    WidgetsBinding.instance.removeObserver(this);

    // Save position only if handler was successfully initialized
    if (_isHandlerInitialized && _audioHandler != null) {
      _audioHandler!.customAction('savePosition');
      debugPrint("PlayerScreen: Requested position save on dispose.");
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint("PlayerScreen: App lifecycle changed to: $state");

    // Save position only if handler was successfully initialized
    if (!_isHandlerInitialized || _audioHandler == null) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _audioHandler!.customAction('savePosition');
        debugPrint(
          "PlayerScreen: Requested position save due to lifecycle state: $state",
        );
        break;
      case AppLifecycleState.resumed:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      "PlayerScreen: build executing... _isLoading=$_isLoading, _isHandlerInitialized=$_isHandlerInitialized",
    );

    final String audiobookTitle =
        _isLoading ? "Loading..." : (_audiobook?.title ?? "Audiobook Player");

    // Use the flag to determine readiness, ensuring handler is not null if ready
    final bool handlerReady = _isHandlerInitialized && _audioHandler != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(audiobookTitle, style: const TextStyle(fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: "Back to Library",
          onPressed: () {
            // Save position only if handler is ready
            if (handlerReady) _audioHandler!.customAction('savePosition');
            if (Navigator.canPop(context)) Navigator.of(context).pop();
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined),
            tooltip: "Stop Playback",
            // Disable if handler not ready
            onPressed:
                !handlerReady
                    ? null
                    : () {
                      _audioHandler!.stop();
                      if (Navigator.canPop(context)) {
                        Navigator.of(context).pop();
                      }
                    },
          ),
        ],
      ),
      // Show loading indicator, error message, or the player content
      body:
          _isLoading
              ? _buildLoadingWidget()
              : (_errorMessage != null
                  ? _buildErrorWidget()
                  : (!handlerReady
                      ? _buildErrorWidget(
                        customMessage: "Audio player not initialized properly",
                      )
                      : _buildPlayerContent(_audioHandler!))),
    );
  }

  Widget _buildLoadingWidget() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 15),
          Text("Loading Player..."),
        ],
      ),
    );
  }

  Widget _buildErrorWidget({String? customMessage}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.orange),
            const SizedBox(height: 20),
            Text(
              customMessage ?? _errorMessage ?? "An error occurred",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text("Try Again"),
              onPressed: _canRetry ? _retryInitialization : null,
            ),
            const SizedBox(height: 12),
            TextButton(
              child: const Text("Go Back"),
              onPressed: () {
                if (Navigator.canPop(context)) {
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the main content widget when the player is ready.
  Widget _buildPlayerContent(MyAudioHandler handler) {
    debugPrint("PlayerScreen: _buildPlayerContent executing...");

    // This check should ideally not be needed if _isLoading=false guarantees _audiobook is set.
    if (_audiobook == null) {
      debugPrint(
        "PlayerScreen: ERROR - _audiobook is null in _buildPlayerContent",
      );
      return const Center(
        child: Text("Error: Audiobook data unavailable. Please go back."),
      );
    }

    // --- Main Player UI Column ---
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          // --- Cover Art ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: buildCoverWidget(
                context, // Pass context needed by helper
                _audiobook!,
                size: MediaQuery.of(context).size.width * 0.6,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // --- Current Chapter Title ---
          StreamBuilder<MediaItem?>(
            stream: handler.mediaItem,
            builder: (context, snapshot) {
              final currentItem = snapshot.data;
              final title =
                  currentItem?.title ??
                  (_audiobook!.chapters.isNotEmpty
                      ? "Ready to play"
                      : "No chapters found");
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
          const SizedBox(height: 5),

          // --- Audiobook Title (Static) ---
          Text(
            _audiobook!.title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: Colors.grey[400]),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),

          // --- Seek Bar ---
          StreamBuilder<PositionData>(
            stream: _positionDataStream,
            builder: (context, snapshot) {
              final positionData =
                  snapshot.data ??
                  PositionData(Duration.zero, Duration.zero, Duration.zero);
              return SeekBar(
                duration: positionData.duration,
                position: positionData.position,
                bufferedPosition: positionData.bufferedPosition,
                onChangeEnd: handler.seek,
              );
            },
          ),
          const SizedBox(height: 10),

          // --- Player Controls ---
          StreamBuilder<PlaybackState>(
            stream: handler.playbackState,
            builder: (context, snapshot) {
              final state = snapshot.data ?? PlaybackState();
              return StreamBuilder<MediaItem?>(
                stream: handler.mediaItem,
                builder: (context, mediaSnapshot) {
                  return PlayerControls(
                    audioHandler: handler,
                    state: state,
                    mediaItem: mediaSnapshot.data,
                  );
                },
              );
            },
          ),
          const SizedBox(height: 10),

          // --- Chapter List ---
          Expanded(
            child: StreamBuilder<List<MediaItem>>(
              stream: handler.queue,
              builder: (context, snapshot) {
                final queue = snapshot.data ?? [];
                final List<MediaItem> displayChapters =
                    (queue.isEmpty && _audiobook!.chapters.isNotEmpty)
                        ? _audiobook!.chapters
                            .map((c) => c.toMediaItem())
                            .toList()
                        : queue;

                if (displayChapters.isEmpty) {
                  return const Center(child: Text("No chapters available."));
                }

                return StreamBuilder<MediaItem?>(
                  stream: handler.mediaItem,
                  builder: (context, currentItemSnapshot) {
                    final currentMediaId = currentItemSnapshot.data?.id;
                    return _buildChapterList(
                      displayChapters,
                      currentMediaId,
                      handler,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the list view for displaying chapters.
  Widget _buildChapterList(
    List<MediaItem> chapters,
    String? currentMediaId,
    MyAudioHandler handler,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16.0),
      itemCount: chapters.length,
      itemBuilder: (context, index) {
        final chapterItem = chapters[index];
        final isPlaying = chapterItem.id == currentMediaId;

        return ListTile(
          leading:
              isPlaying
                  ? Icon(
                    Icons.play_arrow,
                    color: Theme.of(context).colorScheme.primary,
                  )
                  : Icon(Icons.music_note_outlined, color: Colors.grey[500]),
          title: Text(
            chapterItem.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
              color: isPlaying ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
          trailing: Text(
            formatDuration(chapterItem.duration),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          tileColor:
              isPlaying
                  ? Theme.of(context).colorScheme.primary.withAlpha(25)
                  : null,
          dense: true,
          onTap: () {
            debugPrint(
              "PlayerScreen: Tapped Chapter: ${chapterItem.title} (Index $index)",
            );
            handler.skipToQueueItem(index);
          },
        );
      },
    );
  }
}
