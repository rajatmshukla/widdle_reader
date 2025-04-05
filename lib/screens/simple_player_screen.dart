import 'package:flutter/material.dart';
import '../models/audiobook.dart';
import '../services/simple_audio_service.dart';
import '../utils/helpers.dart';

class SimplePlayerScreen extends StatefulWidget {
  const SimplePlayerScreen({super.key});

  @override
  State<SimplePlayerScreen> createState() => _SimplePlayerScreenState();
}

class _SimplePlayerScreenState extends State<SimplePlayerScreen>
    with WidgetsBindingObserver {
  final _audioService = SimpleAudioService();
  Audiobook? _audiobook;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isSpeedControlExpanded = false;
  bool _canRetry = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAudiobook();
    });
  }

  Future<void> _loadAudiobook() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final args = ModalRoute.of(context)?.settings.arguments;
      if (args == null || args is! Map<String, dynamic>) {
        throw Exception("Invalid arguments");
      }

      _audiobook = args['audiobook'] as Audiobook?;
      final startChapterId = args['startChapterId'] as String?;
      final startPosition = args['startPosition'] as Duration?;

      if (_audiobook == null) {
        throw Exception("Audiobook data missing");
      }

      // Find the chapter index from the ID
      int startChapterIndex = 0;
      if (startChapterId != null) {
        startChapterIndex = _audiobook!.chapters.indexWhere(
          (c) => c.id == startChapterId,
        );
        if (startChapterIndex == -1) startChapterIndex = 0;
      }

      // Load the audiobook
      await _audioService.loadAudiobook(
        _audiobook!,
        startChapter: startChapterIndex,
        startPosition: startPosition,
      );

      // Enable notifications for this playback session
      await _audioService.enableNotifications();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Failed to load audiobook: $e";
        });
      }
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

    _loadAudiobook();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Don't stop playback, just detach UI
    _audioService.detachFromUI();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // App going to background or being killed
        _audioService.saveCurrentPosition();
        break;
      case AppLifecycleState.resumed:
        // App coming back to foreground
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_audiobook?.title ?? "Audiobook Player"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _audioService.saveCurrentPosition();
            Navigator.of(context).pop();
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined),
            onPressed: () {
              _audioService.stop();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body:
          _isLoading
              ? _buildLoadingWidget()
              : (_errorMessage != null
                  ? _buildErrorWidget()
                  : _buildPlayerContent()),
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

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.orange),
            const SizedBox(height: 20),
            Text(
              _errorMessage ?? "An error occurred",
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
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerContent() {
    if (_audiobook == null) {
      return const Center(child: Text("No audiobook data available"));
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),

          // Cover art
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: buildCoverWidget(
                context,
                _audiobook!,
                size: MediaQuery.of(context).size.width * 0.6,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Chapter title
          StreamBuilder<int>(
            stream: _audioService.currentChapterStream,
            builder: (context, snapshot) {
              final index = snapshot.data ?? 0;
              final title =
                  index < _audiobook!.chapters.length
                      ? _audiobook!.chapters[index].title
                      : "Unknown chapter";

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

          // Audiobook title
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

          // Progress bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildProgressBar(),
          ),

          const SizedBox(height: 16),

          // Speed control button
          Center(child: _buildSpeedControl()),

          const SizedBox(height: 16),

          // Controls
          _buildControls(),

          const SizedBox(height: 10),

          // Chapter list
          Expanded(child: _buildChapterList()),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return StreamBuilder<Duration>(
      stream: _audioService.positionStream,
      builder: (context, positionSnapshot) {
        return StreamBuilder<Duration>(
          stream: _audioService.durationStream,
          builder: (context, durationSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final duration = durationSnapshot.data ?? Duration.zero;

            return Column(
              children: [
                Slider(
                  min: 0,
                  max:
                      duration.inMilliseconds > 0
                          ? duration.inMilliseconds.toDouble()
                          : 1.0,
                  value: position.inMilliseconds.toDouble().clamp(
                    0,
                    duration.inMilliseconds > 0
                        ? duration.inMilliseconds.toDouble()
                        : 1.0,
                  ),
                  onChanged: (value) {
                    _audioService.seek(Duration(milliseconds: value.round()));
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(formatDuration(position)),
                      Text(formatDuration(duration)),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSpeedControl() {
    return StreamBuilder<double>(
      stream: _audioService.speedStream,
      builder: (context, snapshot) {
        final currentSpeed = snapshot.data ?? 1.0;

        return Column(
          children: [
            // Speed button
            GestureDetector(
              onTap: () {
                setState(() {
                  _isSpeedControlExpanded = !_isSpeedControlExpanded;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.5),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  "${currentSpeed.toStringAsFixed(1)}×",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),

            // Expandable speed slider
            AnimatedCrossFade(
              firstChild: const SizedBox(height: 0, width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("0.5×", style: TextStyle(fontSize: 12)),
                        Text(
                          "${currentSpeed.toStringAsFixed(1)}×",
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text("2.0×", style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    Slider(
                      min: 0.5,
                      max: 2.0,
                      divisions: 15, // This creates steps of 0.1
                      value: currentSpeed,
                      onChanged: (value) {
                        _audioService.setSpeed(value);
                      },
                      onChangeEnd: (value) {
                        // Optional: auto-collapse after selecting a speed
                        Future.delayed(const Duration(milliseconds: 500), () {
                          if (mounted) {
                            setState(() {
                              _isSpeedControlExpanded = false;
                            });
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
              crossFadeState:
                  _isSpeedControlExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        );
      },
    );
  }

  Widget _buildControls() {
    return StreamBuilder<bool>(
      stream: _audioService.playingStream,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data ?? false;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.replay_30),
              iconSize: 42,
              onPressed: () => _audioService.rewind(),
            ),
            IconButton(
              icon: const Icon(Icons.skip_previous),
              iconSize: 42,
              onPressed: () => _audioService.skipToPrevious(),
            ),
            IconButton(
              icon: Icon(
                isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled,
              ),
              iconSize: 64,
              onPressed:
                  () =>
                      isPlaying ? _audioService.pause() : _audioService.play(),
            ),
            IconButton(
              icon: const Icon(Icons.skip_next),
              iconSize: 42,
              onPressed: () => _audioService.skipToNext(),
            ),
            IconButton(
              icon: const Icon(Icons.forward_30),
              iconSize: 42,
              onPressed: () => _audioService.fastForward(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildChapterList() {
    return StreamBuilder<int>(
      stream: _audioService.currentChapterStream,
      builder: (context, snapshot) {
        final currentIndex = snapshot.data ?? 0;

        return ListView.builder(
          itemCount: _audiobook!.chapters.length,
          itemBuilder: (context, index) {
            final chapter = _audiobook!.chapters[index];
            final isPlaying = index == currentIndex;

            return ListTile(
              leading:
                  isPlaying
                      ? Icon(
                        Icons.play_arrow,
                        color: Theme.of(context).colorScheme.primary,
                      )
                      : Icon(
                        Icons.music_note_outlined,
                        color: Colors.grey[500],
                      ),
              title: Text(
                chapter.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                  color:
                      isPlaying ? Theme.of(context).colorScheme.primary : null,
                ),
              ),
              trailing: Text(
                formatDuration(chapter.duration ?? Duration.zero),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
              tileColor:
                  isPlaying
                      ? Theme.of(context).colorScheme.primary.withAlpha(25)
                      : null,
              dense: true,
              onTap: () => _audioService.skipToChapter(index),
            );
          },
        );
      },
    );
  }
}
