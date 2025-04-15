import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart'; // Import the package
import '../providers/audiobook_provider.dart';
import '../models/audiobook.dart';
import '../services/simple_audio_service.dart';
import '../utils/helpers.dart';
import '../utils/responsive_utils.dart';
import '../theme.dart';

class SimplePlayerScreen extends StatefulWidget {
  const SimplePlayerScreen({super.key});

  @override
  State<SimplePlayerScreen> createState() => _SimplePlayerScreenState();
}

// Remove the old ScrollController
// final ScrollController _chapterListScrollController = ScrollController();

class _SimplePlayerScreenState extends State<SimplePlayerScreen>
    with WidgetsBindingObserver {
  final _audioService = SimpleAudioService();
  Audiobook? _audiobook;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isSpeedControlExpanded = false;
  bool _canRetry = true;

  // Add ItemScrollController and ItemPositionsListener
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  StreamSubscription<int>?
  _chapterSubscription; // To listen for chapter changes

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAudiobook();
    });

    // Listen to chapter changes to scroll and center the item
    _chapterSubscription = _audioService.currentChapterStream.listen((index) {
      // Add a small delay to ensure the list is built before scrolling
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _itemScrollController.isAttached) {
          // Check if controller is ready and widget is mounted
          _itemScrollController.scrollTo(
            index: index,
            duration: const Duration(milliseconds: 400), // Adjust duration
            curve: Curves.easeInOutCubic, // Adjust curve
            alignment: 0.5, // 0.5 aligns the item to the center
          );
        }
      });
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

      if (mounted) {
        final provider = Provider.of<AudiobookProvider>(context, listen: false);
        await provider.recordBookPlayed(_audiobook!.id);
      }

      int startChapterIndex = 0;
      if (startChapterId != null) {
        startChapterIndex = _audiobook!.chapters.indexWhere(
          (c) => c.id == startChapterId,
        );
        if (startChapterIndex == -1) startChapterIndex = 0;
      }

      await _audioService.loadAudiobook(
        _audiobook!,
        startChapter: startChapterIndex,
        startPosition: startPosition,
        autoPlay: false,
      );

      await _audioService.enableNotifications();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        // Remove the old auto-scroll logic, it's handled by the stream listener now
        /*
        await Future.delayed(const Duration(milliseconds: 100));
        final currentIndex = _audioService.currentChapterIndex;
        if (_chapterListScrollController.hasClients) {
          _chapterListScrollController.animateTo(
            currentIndex * 72.0, // Approx. item height
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
        */
      }
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
    _chapterSubscription?.cancel(); // Cancel the stream subscription
    // _chapterListScrollController.dispose(); // Remove old controller disposal
    WidgetsBinding.instance.removeObserver(this);
    _savePositionBeforeDispose();
    _audioService.detachFromUI();
    super.dispose();
  }

  // Save position before leaving the screen
  Future<void> _savePositionBeforeDispose() async {
    try {
      // Save position to update progress in library
      await _audioService.saveCurrentPosition();

      // If the audiobook is loaded, update its last played timestamp
      if (_audiobook != null && mounted) {
        final provider = Provider.of<AudiobookProvider>(context, listen: false);
        await provider.recordBookPlayed(_audiobook!.id);
      }
    } catch (e) {
      debugPrint("Error in savePositionBeforeDispose: $e");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // App going to background or being killed
        _audioService.saveCurrentPosition();

        // Also update the last played timestamp
        if (_audiobook != null && mounted) {
          final provider = Provider.of<AudiobookProvider>(
            context,
            listen: false,
          );
          provider.recordBookPlayed(_audiobook!.id);
        }
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
    final isLandscape = ResponsiveUtils.isLandscape(context);

    return Scaffold(
      extendBodyBehindAppBar: true, // Let content flow behind app bar
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withAlpha(
                (0.7 * 255).round(),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.arrow_back_rounded),
          ),
          onPressed: () async {
            // Save position and wait for it to complete before popping
            await _audioService.saveCurrentPosition();
            if (mounted) {
              Navigator.of(
                context,
              ).pop(true); // Return with a result to trigger refresh
            }
          },
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withAlpha(
                  (0.7 * 255).round(),
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.stop_circle_outlined),
            ),
            onPressed: () async {
              // Save position and wait for it to complete before stopping
              await _audioService.saveCurrentPosition();
              await _audioService.stop();
              if (mounted) {
                Navigator.of(
                  context,
                ).pop(true); // Return with result to trigger refresh
              }
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
                      color: colorScheme.errorContainer.withAlpha(
                        (0.2 * 255).round(),
                      ),
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
                      Navigator.of(context).pop(true); // Return with result
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

    // Use responsive utils to determine layout
    final isLandscape = ResponsiveUtils.isLandscape(context);
    final screenSize = MediaQuery.of(context).size;

    // Use different layouts for portrait and landscape orientations
    return Container(
      decoration: AppTheme.gradientBackground(context),
      child: SafeArea(
        child:
            isLandscape
                ? _buildLandscapeLayout(colorScheme, screenSize)
                : _buildPortraitLayout(colorScheme, screenSize),
      ),
    );
  }

  Widget _buildPortraitLayout(ColorScheme colorScheme, Size screenSize) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            children: [
              const SizedBox(height: 10),

              // Cover art
              Container(
                width: screenSize.width * 0.5,
                height: screenSize.width * 0.5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha((0.3 * 255).round()),
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
                    size: screenSize.width * 0.5,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              _buildChapterTitle(colorScheme),
              const SizedBox(height: 5),
              _buildAudiobookTitle(colorScheme),
              const SizedBox(height: 16),
              _buildProgressBar(colorScheme),
              const SizedBox(height: 16),
              _buildSpeedControl(colorScheme),
              const SizedBox(height: 24),
              _buildControls(colorScheme),
              const SizedBox(height: 24),

              // Chapter header
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.library_books_outlined,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Chapters",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Flexible scrollable chapter list (independent from the rest)
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: colorScheme.surfaceContainerLowest.withOpacity(0.3),
                  ),
                  child: _buildChapterList(colorScheme),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  // Update the _buildLandscapeLayout method in SimplePlayerScreen
  Widget _buildLandscapeLayout(ColorScheme colorScheme, Size screenSize) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left side - Cover and controls with independent scrolling
        Expanded(
          flex: 45, // Takes 45% of the width
          child: SafeArea(
            child: ListView(
              // Use ListView for independent scrolling
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              physics: const BouncingScrollPhysics(),
              children: [
                // Cover art - smaller in landscape
                Center(
                  child: Container(
                    width: screenSize.height * 0.35, // Use height for scaling
                    height: screenSize.height * 0.35, // Maintain aspect ratio
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha((0.3 * 255).round()),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: buildCoverWidget(
                        context,
                        _audiobook!,
                        size: screenSize.height * 0.35,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Chapter and book title
                Center(
                  child: Column(
                    children: [
                      _buildChapterTitle(colorScheme),
                      const SizedBox(height: 4),
                      _buildAudiobookTitle(colorScheme),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Progress bar
                _buildProgressBar(colorScheme),

                const SizedBox(height: 16),

                // Speed control with wider layout
                _buildSpeedControl(colorScheme),

                const SizedBox(height: 16),

                // Controls
                _buildControls(colorScheme),

                // Extra bottom padding
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),

        // Vertical divider
        Container(
          height: screenSize.height, // Ensure divider spans height
          width: 1,
          color: colorScheme.outline.withOpacity(0.3),
        ),

        // Right side - Chapter list with matching portrait styling
        Expanded(
          flex: 55,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Heading
                  Row(
                    children: [
                      Icon(
                        Icons.library_books_outlined,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Chapters",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Chapter list container styled like portrait mode
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: colorScheme.surfaceContainerLowest.withOpacity(
                          0.3,
                        ),
                      ),
                      child: _buildChapterList(colorScheme), // Pass controllers
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // UPDATE _buildChapterList
  Widget _buildChapterList(ColorScheme colorScheme) {
    final int totalChapters = _audiobook?.chapters.length ?? 0;

    // Use ScrollablePositionedList.builder
    return ScrollablePositionedList.builder(
      itemCount: totalChapters,
      itemScrollController: _itemScrollController, // Assign controller
      itemPositionsListener: _itemPositionsListener, // Assign listener
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 80),
      itemBuilder: (context, index) {
        // Get chapter data safely
        if (_audiobook == null || index >= _audiobook!.chapters.length) {
          return const SizedBox.shrink(); // Handle edge case
        }
        final chapter = _audiobook!.chapters[index];

        // Use a StreamBuilder just for the 'isPlaying' status to react immediately
        return StreamBuilder<int>(
          stream: _audioService.currentChapterStream,
          // Use currentChapterIndex as initial data for smoother loading
          initialData: _audioService.currentChapterIndex,
          builder: (context, snapshot) {
            final currentPlayingIndex =
                snapshot.data ?? _audioService.currentChapterIndex;
            final isPlaying = index == currentPlayingIndex;

            // Your ListTile code remains largely the same:
            return ListTile(
              dense: context.isLandscape,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: context.isLandscape ? 0 : 2,
              ),
              leading: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color:
                      isPlaying
                          ? colorScheme.primary
                          : colorScheme.surfaceContainerHighest.withAlpha(150),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    isPlaying
                        ? Icons
                            .play_arrow_rounded // Use consistent icons
                        : Icons.my_library_books_rounded,
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
                  fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                  color:
                      isPlaying ? colorScheme.primary : colorScheme.onSurface,
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
              selectedTileColor: colorScheme.primaryContainer.withAlpha(80),
              onTap: () {
                _audioService.skipToChapter(index);
                // Scrolling is now handled by the stream listener in initState
                // _audioService.saveCurrentPosition(); // Optionally save position on manual tap
              },
            );
          },
        );
      },
    );
  }

  // --- Other helper methods remain the same ---

  Widget _buildChapterTitle(ColorScheme colorScheme) {
    return StreamBuilder<int>(
      stream: _audioService.currentChapterStream,
      builder: (context, snapshot) {
        final index =
            snapshot.data ??
            _audioService.currentChapterIndex; // Use initial value
        final title =
            (_audiobook != null &&
                    index >= 0 &&
                    index < _audiobook!.chapters.length)
                ? _audiobook!.chapters[index].title
                : "Loading chapter..."; // Handle loading/edge cases

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: animation.drive(Tween<double>(begin: 0.9, end: 1.0)),
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
                fontSize: context.isLandscape ? 16 : 18, // Smaller in landscape
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
    );
  }

  Widget _buildAudiobookTitle(ColorScheme colorScheme) {
    return Text(
      _audiobook?.title ?? "Audiobook", // Handle null audiobook
      style: TextStyle(
        fontSize: context.isLandscape ? 12 : 14, // Smaller in landscape
        fontWeight: FontWeight.w400,
        color: colorScheme.onSurface.withAlpha((0.7 * 255).round()),
        letterSpacing: 0.2,
      ),
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
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

            // Calculate overall audiobook progress if available
            final totalDuration = _audiobook?.totalDuration ?? Duration.zero;

            // Find cumulative position (add up previous chapters + current position)
            Duration cumulativePosition = Duration.zero;
            if (_audiobook != null) {
              final currentIndex = _audioService.currentChapterIndex;
              // Ensure currentIndex is valid before iterating
              if (currentIndex >= 0) {
                for (int i = 0; i < currentIndex; i++) {
                  if (i < _audiobook!.chapters.length &&
                      _audiobook!.chapters[i].duration != null) {
                    cumulativePosition += _audiobook!.chapters[i].duration!;
                  }
                }
                cumulativePosition += position;
              } else {
                // If index is invalid (e.g., -1), maybe just show current chapter position
                cumulativePosition = position;
              }
            }

            // Use responsive layout
            final isLandscape = context.isLandscape;
            final compactLayout = isLandscape;

            return Column(
              children: [
                // Overall audiobook progress indicator
                if (totalDuration.inMilliseconds > 0)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      compactLayout ? 4 : 8,
                    ),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: compactLayout ? 4 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withOpacity(
                          0.7,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        formatProgressFraction(
                          cumulativePosition,
                          totalDuration,
                        ),
                        style: TextStyle(
                          fontSize: compactLayout ? 10 : 12,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.primary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),

                // Progress bar
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4,
                    activeTrackColor: colorScheme.primary,
                    inactiveTrackColor: colorScheme.onSurface.withOpacity(0.2),
                    thumbColor: colorScheme.primary,
                    thumbShape: RoundSliderThumbShape(
                      enabledThumbRadius: compactLayout ? 6 : 8,
                      elevation: 4,
                      pressedElevation: 8,
                    ),
                    overlayColor: colorScheme.primary.withOpacity(0.2),
                    overlayShape: RoundSliderOverlayShape(
                      overlayRadius: compactLayout ? 12 : 16,
                    ),
                  ),
                  child: Slider(
                    min: 0,
                    max:
                        duration.inMilliseconds > 0
                            ? duration.inMilliseconds.toDouble()
                            : 1.0, // Avoid division by zero if duration is 0
                    value: position.inMilliseconds.toDouble().clamp(
                      0,
                      duration.inMilliseconds > 0
                          ? duration.inMilliseconds.toDouble()
                          : 1.0, // Clamp value within valid range
                    ),
                    onChanged: (value) {
                      // Only seek if duration is valid
                      if (duration.inMilliseconds > 0) {
                        _audioService.seek(
                          Duration(milliseconds: value.round()),
                        );
                      }
                    },
                    onChangeEnd: (value) {
                      // Save position when user manually seeks
                      _audioService.saveCurrentPosition();
                    },
                  ),
                ),

                // Time labels
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        formatDetailedDuration(position),
                        style: TextStyle(
                          fontSize: compactLayout ? 10 : 12,
                          color: colorScheme.primary.withOpacity(0.8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        formatDetailedDuration(duration),
                        style: TextStyle(
                          fontSize: compactLayout ? 10 : 12,
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
        final isLandscape = context.isLandscape;

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
                padding: EdgeInsets.symmetric(
                  horizontal: isLandscape ? 12 : 16,
                  vertical: isLandscape ? 6 : 8,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primary, // Match play/pause button
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withAlpha((0.3 * 255).round()),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "${currentSpeed.toStringAsFixed(1)}×",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isLandscape ? 12 : 14,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _isSpeedControlExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: isLandscape ? 14 : 16,
                      color: colorScheme.onPrimary,
                    ),
                  ],
                ),
              ),
            ),

            // Expandable speed slider
            AnimatedCrossFade(
              firstChild: const SizedBox(height: 0, width: double.infinity),
              secondChild: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  isLandscape ? 8 : 16,
                  20,
                  isLandscape ? 4 : 8,
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "0.5×",
                          style: TextStyle(
                            fontSize: isLandscape ? 10 : 12,
                            color: colorScheme.onSurface.withAlpha(
                              (0.7 * 255).round(),
                            ),
                          ),
                        ),
                        Text(
                          "2.0×",
                          style: TextStyle(
                            fontSize: isLandscape ? 10 : 12,
                            color: colorScheme.onSurface.withAlpha(
                              (0.7 * 255).round(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 4,
                        activeTrackColor: colorScheme.primary,
                        inactiveTrackColor: colorScheme.onSurface.withAlpha(
                          (0.2 * 255).round(),
                        ),
                        thumbColor: colorScheme.primary,
                        thumbShape: RoundSliderThumbShape(
                          enabledThumbRadius: isLandscape ? 6 : 8,
                        ),
                        overlayColor: colorScheme.primary.withAlpha(
                          (0.2 * 255).round(),
                        ),
                        overlayShape: RoundSliderOverlayShape(
                          overlayRadius: isLandscape ? 12 : 16,
                        ),
                      ),
                      child: Slider(
                        min: 0.5,
                        max: 2.0,
                        divisions: 15, // Steps of 0.1
                        value: currentSpeed.clamp(
                          0.5,
                          2.0,
                        ), // Ensure value is within bounds
                        onChanged: (value) {
                          _audioService.setSpeed(value);
                        },
                        onChangeEnd: (value) {
                          // Optional: auto-collapse
                          // Future.delayed(const Duration(milliseconds: 500), () {
                          //   if (mounted) {
                          //     setState(() { _isSpeedControlExpanded = false; });
                          //   }
                          // });
                        },
                      ),
                    ),
                  ],
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
    final isLandscape = context.isLandscape;

    return StreamBuilder<bool>(
      stream: _audioService.playingStream,
      builder: (context, snapshot) {
        // Use initial value from service for smoother loading
        final isPlaying = snapshot.data ?? _audioService.isPlaying;

        return Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          margin: EdgeInsets.symmetric(
            horizontal: isLandscape ? 8 : 16,
            vertical: isLandscape ? 4 : 0,
          ),
          color: colorScheme.surfaceContainerHighest.withAlpha(
            (0.7 * 255).round(),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: isLandscape ? 4 : 8,
              horizontal: isLandscape ? 4 : 8,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Rewind button
                _buildControlButton(
                  icon: Icons.replay_30_rounded,
                  size: isLandscape ? 28 : 32,
                  color: colorScheme.onSurfaceVariant,
                  onPressed: () => _audioService.rewind(),
                ),

                // Previous chapter button
                _buildControlButton(
                  icon: Icons.skip_previous_rounded,
                  size: isLandscape ? 28 : 32,
                  color: colorScheme.onSurfaceVariant,
                  onPressed: () {
                    _audioService.skipToPrevious();
                    _audioService.saveCurrentPosition(); // Save position
                  },
                ),

                // Play/Pause button
                Container(
                  width: isLandscape ? 52 : 64,
                  height: isLandscape ? 52 : 64,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withAlpha(
                          (0.3 * 255).round(),
                        ),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: AnimatedSwitcher(
                      duration: const Duration(
                        milliseconds: 200,
                      ), // Faster animation
                      child: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        key: ValueKey<bool>(isPlaying), // Key for animation
                        size: isLandscape ? 30 : 36,
                        color: colorScheme.onPrimary,
                      ),
                      transitionBuilder: (child, animation) {
                        return ScaleTransition(scale: animation, child: child);
                      },
                    ),
                    onPressed: () {
                      isPlaying ? _audioService.pause() : _audioService.play();
                      // Save position after play/pause state changes
                      _audioService.saveCurrentPosition();
                    },
                  ),
                ),

                // Next chapter button
                _buildControlButton(
                  icon: Icons.skip_next_rounded,
                  size: isLandscape ? 28 : 32,
                  color: colorScheme.onSurfaceVariant,
                  onPressed: () {
                    _audioService.skipToNext();
                    _audioService.saveCurrentPosition(); // Save position
                  },
                ),

                // Fast forward button
                _buildControlButton(
                  icon: Icons.forward_30_rounded,
                  size: isLandscape ? 28 : 32,
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
        borderRadius: BorderRadius.circular(30), // Make the tap area larger
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(8.0), // Standard padding
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
  }
}
