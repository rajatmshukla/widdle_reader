import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'dart:async'; // Import for Future.delayed

// Import local models, handler, widgets, and helpers
import '../models/audiobook.dart';
import '../services/audio_handler.dart'; // Import handler and getAudioHandlerInstance
// *** POTENTIAL FIX: Ensure correct relative path for PlayerControls ***
// If PlayerControls is in the *same directory* as PlayerScreen, use:
// import 'player_controls.dart';
// If PlayerControls is in a 'widgets' subdirectory relative to 'lib':
import 'player_controls.dart'; // Import player controls widget (assuming it's in lib/widgets)
import '../widgets/seekbar.dart'; // Import seekbar widget and PositionData (assuming it's in lib/widgets)
import '../utils/helpers.dart'; // Import formatDuration and buildCoverWidget

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
  bool _isLoading = true; // Start as true, set to false when ready
  bool _isHandlerInitialized = false; // Tracks if handler instance is obtained

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
    // Initialize handler and load data directly in initState.
    // Using addPostFrameCallback is usually for accessing context-dependent things
    // immediately after build, which isn't strictly necessary here.
    _initializeHandlerAndLoadData();
    debugPrint(
      "PlayerScreen: initState END (called _initializeHandlerAndLoadData)",
    );
  }

  /// Initializes the audio handler reference and loads initial audiobook data.
  Future<void> _initializeHandlerAndLoadData() async {
    debugPrint("PlayerScreen: _initializeHandlerAndLoadData START");
    if (_isHandlerInitialized) {
      debugPrint("PlayerScreen: Handler already initialized. Exiting.");
      return;
    }

    try {
      // *** DIAGNOSTIC: Optional Small Delay ***
      // Keep this delay temporarily if you suspect extreme timing issues.
      // If the error is resolved without it later, you can remove it.
      // const diagnosticDelay = Duration(milliseconds: 50);
      // await Future.delayed(diagnosticDelay);
      // debugPrint("PlayerScreen: Delay finished, attempting getAudioHandlerInstance()...");

      // Get the single handler instance (throws if not ready)
      _audioHandler = getAudioHandlerInstance();
      _isHandlerInitialized =
          true; // Mark as initialized AFTER getting instance
      debugPrint("PlayerScreen: Audio handler instance obtained successfully.");

      // Check if route arguments exist AFTER handler is obtained
      // Use 'mounted' check before accessing context.
      if (!mounted) {
        debugPrint(
          "PlayerScreen: Widget not mounted after getting handler. Exiting.",
        );
        return;
      }
      // It's safer to check context availability before calling ModalRoute.of
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
        debugPrint(
          "PlayerScreen: Setting _isLoading to false and calling setState...",
        );
        setState(() {
          _isLoading = false;
        });
        debugPrint("PlayerScreen: setState called.");
      } else {
        debugPrint(
          "PlayerScreen: Widget not mounted before final setState. Cannot update UI.",
        );
      }
    } catch (e, stackTrace) {
      // Catch errors during initialization (including handler not ready)
      debugPrint("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
      debugPrint(
        "PlayerScreen: ERROR during _initializeHandlerAndLoadData: $e",
      );
      debugPrint("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
      debugPrint("$stackTrace");
      if (mounted) {
        // Set loading false anyway to stop spinner, maybe show error in UI
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error initializing player: ${e.toString()}")),
        );
      }
    } finally {
      debugPrint("PlayerScreen: _initializeHandlerAndLoadData END");
    }
  }

  /// Sends the 'loadPlaylist' custom action to the audio handler.
  Future<void> _loadAudiobookIntoHandler(
    Audiobook book,
    String? startChapterId,
    Duration? startPosition,
  ) async {
    // Handler should be initialized before calling this.
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
    }
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
      // Show loading indicator OR the player content
      body:
          _isLoading || !handlerReady
              ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 15),
                    Text("Loading Player..."),
                  ],
                ),
              )
              // Pass the confirmed non-nullable handler to the content builder
              : _buildPlayerContent(_audioHandler!),
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
                    // Ensure PlayerControls widget exists and is imported correctly
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

// Ensure PositionData class is defined (often placed in seekbar.dart or utils)
// If it's not defined elsewhere, include it here or import it.
// class PositionData {
//   final Duration position;
//   final Duration bufferedPosition;
//   final Duration duration;
//   PositionData(this.position, this.bufferedPosition, this.duration);
// }
