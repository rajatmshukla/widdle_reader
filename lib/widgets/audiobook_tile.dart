import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/audiobook.dart';
import '../utils/helpers.dart';
import '../services/storage_service.dart';
import '../providers/audiobook_provider.dart';

class AudiobookTile extends StatefulWidget {
  final Audiobook audiobook;
  final String? customTitle;
  final VoidCallback? onTap;

  const AudiobookTile({
    super.key,
    required this.audiobook,
    this.customTitle,
    this.onTap,
  });

  @override
  State<AudiobookTile> createState() => _AudiobookTileState();
}

class _AudiobookTileState extends State<AudiobookTile>
    with WidgetsBindingObserver {
  double _progressPercentage = 0.0;
  bool _isLoadingProgress = true;
  final StorageService _storageService = StorageService();

  @override
  void initState() {
    super.initState();
    // Register as an observer to detect app lifecycle changes
    WidgetsBinding.instance.addObserver(this);
    // Add a post-frame callback to load progress after the first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadListeningProgress();
    });
  }

  @override
  void dispose() {
    // Remove observer when widget is disposed
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(AudiobookTile oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Reload progress if the audiobook changed
    if (oldWidget.audiobook.id != widget.audiobook.id) {
      _loadListeningProgress();
    }
  }

  // This is called when the app lifecycle changes (app comes to foreground, etc.)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came back to foreground, refresh progress
      _loadListeningProgress();
    }
  }

  // Called when this widget becomes visible after being obscured
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // This is a good place to refresh data when returning to this screen
    _loadListeningProgress();
  }

  // Load the listening progress from storage
  // This is a partial update to the AudiobookTile
  // Only showing the modified parts for the completion badge logic

  // Load the listening progress from storage
  Future<void> _loadListeningProgress() async {
    if (!mounted) return;

    // Don't show loading indicator if we already have progress data
    // This prevents flickering when refreshing
    if (_progressPercentage == 0.0) {
      setState(() {
        _isLoadingProgress = true;
      });
    }

    try {
      // Always load position data directly from source for accuracy
      final lastPositionData = await _storageService.loadLastPosition(
        widget.audiobook.id,
      );

      if (lastPositionData != null && mounted) {
        // Find the chapter
        final chapterId = lastPositionData['chapterId'] as String;
        final position = lastPositionData['position'] as Duration;

        // Calculate listened duration up to this point
        Duration listenedDuration = Duration.zero;

        for (final chapter in widget.audiobook.chapters) {
          if (chapter.id == chapterId) {
            // Found the current chapter
            // Add position within current chapter
            listenedDuration += position;
            break;
          } else {
            // Add entire duration of previous chapters
            if (chapter.duration != null) {
              listenedDuration += chapter.duration!;
            }
          }
        }

        // Calculate progress percentage based on total duration
        final totalDuration = widget.audiobook.totalDuration;
        if (totalDuration.inMilliseconds > 0) {
          final progress =
              listenedDuration.inMilliseconds / totalDuration.inMilliseconds;

          // Clamp value between 0 and 1
          final clampedProgress = progress.clamp(0.0, 1.0);

          if (mounted) {
            setState(() {
              _progressPercentage = clampedProgress;
              _isLoadingProgress = false;
            });

            // Store the progress in the cache to use for marking completed books
            await _storageService.saveProgressCache(
              widget.audiobook.id,
              clampedProgress,
            );

            // If progress is ≥99%, update the book completion status in the provider
            if (clampedProgress >= 0.99) {
              final provider = Provider.of<AudiobookProvider>(
                context,
                listen: false,
              );
              await provider.updateCompletionStatus(widget.audiobook.id);
            }
          }
        } else {
          if (mounted) {
            setState(() {
              _progressPercentage = 0.0;
              _isLoadingProgress = false;
            });
          }
        }
      } else {
        // No position data found, set progress to 0
        if (mounted) {
          setState(() {
            _progressPercentage = 0.0;
            _isLoadingProgress = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading progress for ${widget.audiobook.title}: $e");
      if (mounted) {
        setState(() {
          _progressPercentage = 0.0;
          _isLoadingProgress = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Use custom title if provided, otherwise use the original title
    final displayTitle = widget.customTitle ?? widget.audiobook.title;

    // Get the AudiobookProvider to check for new/completed status
    final audiobookProvider = Provider.of<AudiobookProvider>(context);
    final isNew = audiobookProvider.isNewBook(widget.audiobook.id);
    final isCompleted = audiobookProvider.isCompletedBook(widget.audiobook.id);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Card(
        elevation: 4,
        clipBehavior:
            Clip.antiAlias, // Ensures child doesn't overflow rounded corners
        child: Stack(
          children: [
            // Progress indicator background with animated container for smooth transitions
            if (!_isLoadingProgress && _progressPercentage > 0)
              Positioned.fill(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        colorScheme.primary.withOpacity(0.15),
                        Colors.transparent,
                      ],
                      stops: [_progressPercentage, _progressPercentage],
                    ),
                  ),
                ),
              ),

            // Main content
            InkWell(
              onTap: widget.onTap, // Directly use the passed onTap callback
              splashColor: colorScheme.primary.withOpacity(0.3),
              highlightColor: colorScheme.primaryContainer.withOpacity(0.3),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    // Cover image with rounded corners and shadow
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: buildCoverWidget(
                          context,
                          widget.audiobook,
                          size: 80.0,
                          customTitle: displayTitle,
                        ),
                      ),
                    ),

                    const SizedBox(width: 16),

                    // Book details with improved typography
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title with emphasis
                          Text(
                            displayTitle,
                            style: Theme.of(
                              context,
                            ).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),

                          const SizedBox(height: 8),

                          // Progress indicator
                          LayoutBuilder(
                            builder: (context, constraints) {
                              return SizedBox(
                                width: constraints.maxWidth,
                                child: Row(
                                  children: [
                                    // Numeric progress percentage with animation
                                    TweenAnimationBuilder<double>(
                                      duration: const Duration(
                                        milliseconds: 750,
                                      ),
                                      curve: Curves.easeInOut,
                                      tween: Tween<double>(
                                        begin: 0,
                                        end: _progressPercentage * 100,
                                      ),
                                      builder: (context, value, child) {
                                        return Text(
                                          _isLoadingProgress
                                              ? "Loading..."
                                              : "${value.round()}%",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    // Progress bar with animation
                                    Expanded(
                                      child:
                                          _isLoadingProgress
                                              ? const LinearProgressIndicator(
                                                minHeight: 4,
                                              )
                                              : TweenAnimationBuilder<double>(
                                                duration: const Duration(
                                                  milliseconds: 750,
                                                ),
                                                curve: Curves.easeInOut,
                                                tween: Tween<double>(
                                                  begin: 0,
                                                  end: _progressPercentage,
                                                ),
                                                builder: (
                                                  context,
                                                  value,
                                                  child,
                                                ) {
                                                  return ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          2,
                                                        ),
                                                    child: LinearProgressIndicator(
                                                      value: value,
                                                      backgroundColor:
                                                          colorScheme
                                                              .surfaceVariant,
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                            Color
                                                          >(
                                                            colorScheme.primary,
                                                          ),
                                                      minHeight: 4,
                                                    ),
                                                  );
                                                },
                                              ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 8),

                          // Duration with icon
                          Row(
                            children: [
                              Icon(
                                Icons.timer_outlined,
                                size: 14,
                                color: colorScheme.onSurfaceVariant.withOpacity(
                                  0.7,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                formatDuration(widget.audiobook.totalDuration),
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant
                                      .withOpacity(0.7),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Chapter count with icon
                              Icon(
                                Icons.library_books_outlined,
                                size: 14,
                                color: colorScheme.onSurfaceVariant.withOpacity(
                                  0.7,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${widget.audiobook.chapters.length} Chapters',
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant
                                      .withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Right arrow icon
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: colorScheme.primary.withOpacity(0.7),
                    ),
                  ],
                ),
              ),
            ),

            // Top-right corner status indicator (NEW, IN PROGRESS, or COMPLETED)
            Positioned(
              top: 0,
              right: 0,
              child: _buildStatusBadge(
                colorScheme,
                isNew: isNew,
                isCompleted: isCompleted,
                hasProgress: _progressPercentage > 0.01 && !_isLoadingProgress,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build the status badge based on book state
  Widget _buildStatusBadge(
    ColorScheme colorScheme, {
    required bool isNew,
    required bool isCompleted,
    required bool hasProgress,
  }) {
    // If the book is completed (based on provider state or local progress), show COMPLETED badge
    if (isCompleted || _progressPercentage >= 0.99) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.green[700],
          borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(8)),
        ),
        child: const Text(
          'COMPLETED',
          style: TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    // If the book is new, show a NEW badge
    if (isNew) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.yellow[800],
          borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(8)),
        ),
        child: const Text(
          'NEW',
          style: TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    // If the book has progress but is not completed, show an IN PROGRESS badge
    if (hasProgress) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: colorScheme.primary,
          borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(8)),
        ),
        child: const Text(
          'IN PROGRESS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    // If no special status, return an empty container
    return const SizedBox.shrink();
  }
}
