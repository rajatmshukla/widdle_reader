// lib/screens/simple_player_screen.dart
import 'package:flutter/material.dart';
import '../models/audiobook.dart';
import '../services/simple_audio_service.dart';
import '../utils/helpers.dart';

class SimplePlayerScreen extends StatefulWidget {
  const SimplePlayerScreen({super.key});

  @override
  State<SimplePlayerScreen> createState() => _SimplePlayerScreenState();
}

class _SimplePlayerScreenState extends State<SimplePlayerScreen> {
  final _audioService = SimpleAudioService();
  Audiobook? _audiobook;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
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

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Failed to load audiobook: $e";
      });
    }
  }

  @override
  void dispose() {
    // Save position before leaving
    _audioService.saveCurrentPosition();
    _audioService.pause();
    super.dispose();
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
              ? const Center(child: CircularProgressIndicator())
              : (_errorMessage != null
                  ? _buildErrorWidget()
                  : _buildPlayerContent()),
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
              onPressed: _loadAudiobook,
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

          const SizedBox(height: 5),

          // Speed control - Add this line
          _buildSpeedControl(),

          const SizedBox(height: 5),

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
                  max: duration.inMilliseconds.toDouble(),
                  value: position.inMilliseconds.toDouble().clamp(
                    0,
                    duration.inMilliseconds.toDouble(),
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

  Widget _buildSpeedControl() {
    return StreamBuilder<double>(
      stream: _audioService.speedStream,
      builder: (context, snapshot) {
        final currentSpeed = snapshot.data ?? 1.0;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Speed:",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "${currentSpeed.toStringAsFixed(1)}x",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            Slider(
              min: 0.5,
              max: 2.0,
              divisions:
                  15, // This creates steps of 0.1 (15 steps between 0.5 and 2.0)
              value: currentSpeed,
              label: "${currentSpeed.toStringAsFixed(1)}x",
              onChanged: (value) {
                _audioService.setSpeed(value);
              },
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
