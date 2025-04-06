import 'package:flutter/material.dart';
import '../models/audiobook.dart';
import '../services/simple_audio_service.dart';
import '../utils/helpers.dart';
import '../theme.dart';

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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true, // Let content flow behind app bar
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.arrow_back_rounded),
          ),
          onPressed: () {
            _audioService.saveCurrentPosition();
            Navigator.of(context).pop();
          },
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.stop_circle_outlined),
            ),
            onPressed: () {
              _audioService.stop();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body:
          _isLoading
              ? _buildLoadingWidget(colorScheme)
              : (_errorMessage != null
                  ? _buildErrorWidget(colorScheme)
                  : _buildPlayerContent(colorScheme)),
    );
  }

  Widget _buildLoadingWidget(ColorScheme colorScheme) {
    return Container(
      decoration: AppTheme.gradientBackground(context),
      child: Center(
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: colorScheme.primary,
                  strokeWidth: 3,
                ),
                const SizedBox(height: 24),
                Text(
                  "Loading Player...",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget(ColorScheme colorScheme) {
    return Container(
      decoration: AppTheme.gradientBackground(context),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _errorMessage ?? "An error occurred",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text("Try Again"),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
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
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerContent(ColorScheme colorScheme) {
    if (_audiobook == null) {
      return Center(child: Text("No audiobook data available"));
    }

    return Container(
      decoration: AppTheme.gradientBackground(context),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 10),

            // Cover art - made smaller as requested
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40.0),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.5, // Smaller cover
                height:
                    MediaQuery.of(context).size.width *
                    0.5, // Maintain aspect ratio
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: buildCoverWidget(
                    context,
                    _audiobook!,
                    size: MediaQuery.of(context).size.width * 0.5,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Chapter title with animated switching
            StreamBuilder<int>(
              stream: _audioService.currentChapterStream,
              builder: (context, snapshot) {
                final index = snapshot.data ?? 0;
                final title =
                    index < _audiobook!.chapters.length
                        ? _audiobook!.chapters[index].title
                        : "Unknown chapter";

                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeInOut,
                  switchOutCurve: Curves.easeInOut,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: animation.drive(
                          Tween<double>(begin: 0.9, end: 1.0),
                        ),
                        child: child,
                      ),
                    );
                  },
                  child: Padding(
                    key: ValueKey<int>(index), // Important for animation
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 18, // Smaller title
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                        color: colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 5),

            // Audiobook title
            Text(
              _audiobook!.title,
              style: TextStyle(
                fontSize: 14, // Smaller subtitle
                fontWeight: FontWeight.w400,
                color: colorScheme.onSurface.withOpacity(0.7),
                letterSpacing: 0.2,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 16),

            // Progress bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _buildProgressBar(colorScheme),
            ),

            const SizedBox(height: 8),

            // Speed control button
            Center(child: _buildSpeedControl(colorScheme)),

            const SizedBox(height: 16),

            // Controls
            _buildControls(colorScheme),

            const SizedBox(height: 16),

            // Chapter list - no container as requested
            Expanded(
              child: StreamBuilder<int>(
                stream: _audioService.currentChapterStream,
                builder: (context, snapshot) {
                  final currentIndex = snapshot.data ?? 0;

                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 8),
                    physics: const BouncingScrollPhysics(),
                    itemCount: _audiobook!.chapters.length,
                    itemBuilder: (context, index) {
                      final chapter = _audiobook!.chapters[index];
                      final isPlaying = index == currentIndex;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        leading: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color:
                                isPlaying
                                    ? colorScheme.primary
                                    : colorScheme.surfaceContainerHighest
                                        .withOpacity(0.6),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Icon(
                              isPlaying ? Icons.play_arrow : Icons.music_note,
                              size: 16,
                              color:
                                  isPlaying
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        title: Text(
                          chapter.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                isPlaying ? FontWeight.bold : FontWeight.normal,
                            color:
                                isPlaying
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                          ),
                        ),
                        trailing: Text(
                          formatDuration(chapter.duration ?? Duration.zero),
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        selected: isPlaying,
                        selectedTileColor: colorScheme.primaryContainer
                            .withOpacity(0.3),
                        onTap: () => _audioService.skipToChapter(index),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar(ColorScheme colorScheme) {
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
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4,
                    activeTrackColor: colorScheme.primary,
                    inactiveTrackColor: colorScheme.onSurface.withOpacity(0.2),
                    thumbColor: colorScheme.primary,
                    thumbShape: RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                      elevation: 4,
                      pressedElevation: 8,
                    ),
                    overlayColor: colorScheme.primary.withOpacity(0.2),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16,
                    ),
                  ),
                  child: Slider(
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
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        formatDuration(position),
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                      Text(
                        formatDuration(duration),
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
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

  Widget _buildSpeedControl(ColorScheme colorScheme) {
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
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color:
                      _isSpeedControlExpanded
                          ? colorScheme.primaryContainer
                          : colorScheme.surface.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colorScheme.primary.withOpacity(0.5),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "${currentSpeed.toStringAsFixed(1)}×",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color:
                            _isSpeedControlExpanded
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _isSpeedControlExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color:
                          _isSpeedControlExpanded
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),

            // Expandable speed slider
            AnimatedCrossFade(
              firstChild: const SizedBox(height: 0, width: double.infinity),
              secondChild: Card(
                margin: const EdgeInsets.only(top: 8, left: 20, right: 20),
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "0.5×",
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              "${currentSpeed.toStringAsFixed(1)}×",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          Text(
                            "2.0×",
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 4,
                          activeTrackColor: colorScheme.primary,
                          inactiveTrackColor: colorScheme.onSurface.withOpacity(
                            0.2,
                          ),
                          thumbColor: colorScheme.primary,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8,
                          ),
                          overlayColor: colorScheme.primary.withOpacity(0.2),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 16,
                          ),
                        ),
                        child: Slider(
                          min: 0.5,
                          max: 2.0,
                          divisions: 15, // This creates steps of 0.1
                          value: currentSpeed,
                          onChanged: (value) {
                            _audioService.setSpeed(value);
                          },
                          onChangeEnd: (value) {
                            // Optional: auto-collapse after selecting a speed
                            Future.delayed(
                              const Duration(milliseconds: 500),
                              () {
                                if (mounted) {
                                  setState(() {
                                    _isSpeedControlExpanded = false;
                                  });
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              crossFadeState:
                  _isSpeedControlExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 300),
            ),
          ],
        );
      },
    );
  }

  Widget _buildControls(ColorScheme colorScheme) {
    return StreamBuilder<bool>(
      stream: _audioService.playingStream,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data ?? false;

        return Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 16),
          color: colorScheme.surfaceContainerHighest.withOpacity(0.7),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Rewind button
                _buildControlButton(
                  icon: Icons.replay_30_rounded,
                  size: 32,
                  color: colorScheme.onSurfaceVariant,
                  onPressed: () => _audioService.rewind(),
                ),

                // Previous chapter button
                _buildControlButton(
                  icon: Icons.skip_previous_rounded,
                  size: 32,
                  color: colorScheme.onSurfaceVariant,
                  onPressed: () => _audioService.skipToPrevious(),
                ),

                // Play/Pause button
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        key: ValueKey<bool>(isPlaying),
                        size: 36,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                    onPressed:
                        () =>
                            isPlaying
                                ? _audioService.pause()
                                : _audioService.play(),
                  ),
                ),

                // Next chapter button
                _buildControlButton(
                  icon: Icons.skip_next_rounded,
                  size: 32,
                  color: colorScheme.onSurfaceVariant,
                  onPressed: () => _audioService.skipToNext(),
                ),

                // Fast forward button
                _buildControlButton(
                  icon: Icons.forward_30_rounded,
                  size: 32,
                  color: colorScheme.onSurfaceVariant,
                  onPressed: () => _audioService.fastForward(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required double size,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
  }
}
