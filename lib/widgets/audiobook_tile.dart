import 'package:flutter/material.dart';
import 'package:provider/provider.dart' as provider;
import '../models/audiobook.dart';
import '../utils/helpers.dart';
import '../services/storage_service.dart';
import '../providers/audiobook_provider.dart';
import '../utils/responsive_utils.dart';
import '../screens/cover_selection_screen.dart';

class AudiobookTile extends StatefulWidget {
  final Audiobook audiobook;
  final String customTitle;
  final VoidCallback? onTap;

  final bool isGridView;

  const AudiobookTile({
    super.key,
    required this.audiobook,
    required this.customTitle,
    this.onTap,
    this.isGridView = false,
  });

  @override
  State<AudiobookTile> createState() => _AudiobookTileState();
}

class _AudiobookTileState extends State<AudiobookTile>
    with WidgetsBindingObserver {
  double _progressPercentage = 0.0;
  bool _isLoadingProgress = true;
  final StorageService _storageService = StorageService();
  // Track the last time we loaded progress to avoid reloading too frequently
  DateTime _lastProgressLoad = DateTime.now().subtract(const Duration(minutes: 5));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        _loadListeningProgress(forceReload: true);
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(AudiobookTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audiobook.id != widget.audiobook.id) {
      _loadListeningProgress(forceReload: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadListeningProgress(forceReload: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check if we need to reload data - avoid reloading on every rebuild
    final now = DateTime.now();
    if (now.difference(_lastProgressLoad).inSeconds > 2) {
      _loadListeningProgress();
      _lastProgressLoad = now;
    }
  }

  /// Force a progress data reload - call this after any operation that changes progress
  void invalidateProgressData() {
    setState(() {
      _progressPercentage = 0.0;
      _isLoadingProgress = true;
    });
    _loadListeningProgress(forceReload: true);
  }

  /// Loads the listening progress from storage
  /// Set forceReload to true to bypass any caching in the StorageService
  Future<void> _loadListeningProgress({bool forceReload = false}) async {
    if (!mounted) return;

    // Prevent flickering during refresh
    if (_progressPercentage == 0.0) {
      setState(() => _isLoadingProgress = true);
    }

    try {
      // Check if book is marked as completed first - fastest way to determine status
      final isCompleted = await _storageService.isCompleted(widget.audiobook.id);
      
      if (isCompleted && forceReload) {
        // If book is marked as completed, set progress to 100%
        if (mounted) {
          setState(() {
            _progressPercentage = 1.0;
            _isLoadingProgress = false;
          });
        }
        return;
      }
      
      // Try to load from progress cache first (fastest)
      final cachedProgress = await _storageService.loadProgressCache(widget.audiobook.id);
      if (cachedProgress != null) {
        if (mounted) {
          // Set the progress immediately to show changes
          setState(() {
            _progressPercentage = cachedProgress;
            _isLoadingProgress = false;
          });
          
          // If progress is zero or very low, make sure the UI reflects it clearly
          if (cachedProgress < 0.01 && _progressPercentage > 0.01) {
            // Force a second update to ensure the UI shows zero progress
            Future.microtask(() {
              if (mounted) {
                setState(() {
                  _progressPercentage = 0.0;
                });
              }
            });
          }
          return;
        }
      }
      
      // If no cached progress or force reload requested, calculate from position
      final lastPositionData = await _storageService.loadLastPosition(
        widget.audiobook.id,
      );

      if (lastPositionData != null && mounted) {
        final chapterId = lastPositionData['chapterId'] as String;
        final position = lastPositionData['position'] as Duration;
        Duration listenedDuration = Duration.zero;

        // Calculate total listened duration
        for (final chapter in widget.audiobook.chapters) {
          if (chapter.id == chapterId) {
            listenedDuration += position;
            break;
          } else {
            if (chapter.duration != null) {
              listenedDuration += chapter.duration!;
            }
          }
        }

        // Calculate and store progress percentage
        final totalDuration = widget.audiobook.totalDuration;
        if (totalDuration.inMilliseconds > 0) {
          final progress =
              listenedDuration.inMilliseconds / totalDuration.inMilliseconds;
          final clampedProgress = progress.clamp(0.0, 1.0);

          if (mounted) {
            setState(() {
              _progressPercentage = clampedProgress;
              _isLoadingProgress = false;
            });

            await _storageService.saveProgressCache(
              widget.audiobook.id,
              clampedProgress,
            );

            // Update completion status if needed
            if (clampedProgress >= 0.99) {
              final audiobookProvider = provider.Provider.of<AudiobookProvider>(
                context,
                listen: false,
              );
              await audiobookProvider.updateCompletionStatus(widget.audiobook.id);
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
        // No position data found - ensure progress is explicitly set to zero
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
    final displayTitle = widget.customTitle;
    final audiobookProvider = provider.Provider.of<AudiobookProvider>(context);
    final isNew = audiobookProvider.isNewBook(widget.audiobook.id);
    final isCompleted = audiobookProvider.isCompletedBook(widget.audiobook.id);

    // Use grid layout if requested or if in landscape
    if (widget.isGridView) {
      return _buildGridTile(
        context,
        colorScheme,
        displayTitle,
        isNew,
        isCompleted,
      );
    }

    return context.isLandscape
        ? _buildLandscapeTile(
          context,
          colorScheme,
          displayTitle,
          isNew,
          isCompleted,
        )
        : _buildPortraitTile(
          context,
          colorScheme,
          displayTitle,
          isNew,
          isCompleted,
        );
  }

  // Grid layout (vertical card for grid view) - Optimized for accessibility
  Widget _buildGridTile(
    BuildContext context,
    ColorScheme colorScheme,
    String displayTitle,
    bool isNew,
    bool isCompleted,
  ) {
    // Get the text scale factor to adapt layout
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    // For very large fonts, give even more space to text
    final coverFlex = textScale > 1.3 ? 1 : 2;
    final detailsFlex = textScale > 1.3 ? 3 : 2;

    return Card(
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.all(4),
      child: Stack(
        children: [
          // Progress gradient background
          if (!_isLoadingProgress && _progressPercentage > 0)
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cover image area (Takes all remaining space)
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Background blur for cover
                    buildCoverWidget(
                      context,
                      widget.audiobook,
                      size: 200, // Restore scale for quality
                      customTitle: displayTitle,
                    ),
                    // Gradient overlay for text readability at bottom
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.6),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Details area (Takes only what it needs)
              // This ensures bottom padding is small/fixed (5-8px)
              Padding(
                padding: const EdgeInsets.only(left: 8.0, right: 8.0, top: 6.0, bottom: 6.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min, // Wrap content height
                  children: [
                    // Title
                    Text(
                      displayTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: textScale > 1.2 ? 3 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    // Author - only show if font is not extremely large
                    if (widget.audiobook.author != null && textScale <= 1.5)
                      Text(
                        widget.audiobook.author!,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    // Metadata always visible
                    _buildCompactMetadataRow(context, colorScheme),
                    const SizedBox(height: 4),
                    // Progress always visible
                    _buildCompactProgressIndicator(context, colorScheme),
                  ],
                ),
              ),
            ],
          ),

          // Status badge
          Positioned(
            top: 0,
            right: 0,
            child: _buildStatusBadge(
              colorScheme,
              isNew: isNew,
              isCompleted: isCompleted,
              hasProgress: _progressPercentage > 0.01 && !_isLoadingProgress,
              isCompact: true,
            ),
          ),
        ],
      ),
    );
  }

  // Portrait layout (vertical card) - Optimized for accessibility
  Widget _buildPortraitTile(
    BuildContext context,
    ColorScheme colorScheme,
    String displayTitle,
    bool isNew,
    bool isCompleted,
  ) {
    // Get the text scale factor to adapt layout
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    // Reduce cover size for larger fonts
    final coverSize = textScale > 1.3 ? 60.0 : 80.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Card(
        elevation: 4,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Progress gradient background
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
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cover image (smaller for large fonts)
                  _buildCoverImage(context, displayTitle, coverSize),

                  const SizedBox(width: 12),

                  // Book details (expanded area)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Title
                        Text(
                          displayTitle,
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                          maxLines: textScale > 1.2 ? 3 : 2,
                          overflow: TextOverflow.ellipsis,
                        ),

                        const SizedBox(height: 6),

                        // Progress indicator
                        _buildProgressIndicator(context, colorScheme),

                        const SizedBox(height: 6),

                        // Metadata row
                        _buildMetadataRow(context, colorScheme),
                      ],
                    ),
                  ),

                  // Right arrow (smaller)
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: Colors.grey.withOpacity(0.4),
                  ),
                ],
              ),
            ),

            // Status badge (NEW, IN PROGRESS, COMPLETED)
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

  // Landscape layout (compact grid card)
  Widget _buildLandscapeTile(
    BuildContext context,
    ColorScheme colorScheme,
    String displayTitle,
    bool isNew,
    bool isCompleted,
  ) {
    return Card(
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.all(3),
      child: Stack(
        children: [
          // Progress gradient background
          if (!_isLoadingProgress && _progressPercentage > 0)
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top section with cover and title
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      // Cover image (smaller in landscape)
                      _buildCoverImage(context, displayTitle, 60.0),

                      const SizedBox(width: 8),

                      // Title and metadata
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayTitle,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const Spacer(),
                            // Compact metadata row
                            _buildCompactMetadataRow(context, colorScheme),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom section with progress bar
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: _buildCompactProgressIndicator(context, colorScheme),
              ),
            ],
          ),

          // Status badge
          Positioned(
            top: 0,
            right: 0,
            child: _buildStatusBadge(
              colorScheme,
              isNew: isNew,
              isCompleted: isCompleted,
              hasProgress: _progressPercentage > 0.01 && !_isLoadingProgress,
              isCompact: true,
            ),
          ),
        ],
      ),
    );
  }

  // Cover image with shadow and rounded corners
  Widget _buildCoverImage(
    BuildContext context,
    String displayTitle,
    double size,
  ) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.15),
        child: buildCoverWidget(
          context,
          widget.audiobook,
          size: size,
          customTitle: displayTitle,
        ),
      ),
    );
  }

  // Metadata row for portrait mode
  Widget _buildMetadataRow(BuildContext context, ColorScheme colorScheme) {
    final chapterCount = widget.audiobook.chapters.length;
    final chapterText = chapterCount == 1 ? '1 Chapter' : '$chapterCount Chapters';
    
    return Row(
      children: [
        // Duration info
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.timer_outlined,
                size: 14,
                color: colorScheme.onSurfaceVariant.withOpacity(0.7),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  formatDuration(widget.audiobook.totalDuration),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(width: 16),

        // Chapter info - now with more space and prominence
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.library_books_outlined,
                size: 16,
                color: colorScheme.onSurfaceVariant.withOpacity(0.8),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  chapterText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withOpacity(0.8),
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Compact metadata row for landscape mode
  Widget _buildCompactMetadataRow(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    final chapterCount = widget.audiobook.chapters.length;
    final chapterText = chapterCount == 1 ? '1 Chapter' : '$chapterCount Chapters';
    
    return Row(
      children: [
        Icon(
          Icons.timer_outlined,
          size: 12,
          color: colorScheme.onSurfaceVariant.withOpacity(0.7),
        ),
        const SizedBox(width: 2),
        Text(
          formatDuration(widget.audiobook.totalDuration),
          style: TextStyle(
            fontSize: 10,
            color: colorScheme.onSurfaceVariant.withOpacity(0.7),
          ),
        ),
        const SizedBox(width: 6),

        Icon(
          Icons.library_books_outlined,
          size: 12,
          color: colorScheme.onSurfaceVariant.withOpacity(0.7),
        ),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
          chapterText,
          style: TextStyle(
            fontSize: 10,
            color: colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // Progress indicator for portrait layout
  Widget _buildProgressIndicator(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          child: Row(
            children: [
              // Percentage text
              TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 750),
                curve: Curves.easeInOut,
                tween: Tween<double>(begin: 0, end: _progressPercentage * 100),
                builder: (context, value, child) {
                  return Text(
                    _isLoadingProgress ? "Loading..." : "${value.round()}%",
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
              ),

              const SizedBox(width: 8),

              // Progress bar
              Expanded(
                child:
                    _isLoadingProgress
                        ? const LinearProgressIndicator(minHeight: 4)
                        : TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 750),
                          curve: Curves.easeInOut,
                          tween: Tween<double>(
                            begin: 0,
                            end: _progressPercentage,
                          ),
                          builder: (context, value, child) {
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: value,
                                backgroundColor:
                                    colorScheme.surfaceContainerHighest,
                                valueColor: AlwaysStoppedAnimation<Color>(
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
    );
  }

  // Compact progress indicator for landscape layout
  Widget _buildCompactProgressIndicator(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    return Row(
      children: [
        // Percentage text
        Text(
          _isLoadingProgress
              ? "..."
              : "${(_progressPercentage * 100).round()}%",
          style: TextStyle(
            fontSize: 10,
            color: colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(width: 4),

        // Progress bar
        Expanded(
          child:
              _isLoadingProgress
                  ? const LinearProgressIndicator(minHeight: 3)
                  : ClipRRect(
                    borderRadius: BorderRadius.circular(1.5),
                    child: LinearProgressIndicator(
                      value: _progressPercentage,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colorScheme.primary,
                      ),
                      minHeight: 3,
                    ),
                  ),
        ),
      ],
    );
  }

  // Status badge builder
  Widget _buildStatusBadge(
    ColorScheme colorScheme, {
    required bool isNew,
    required bool isCompleted,
    required bool hasProgress,
    bool isCompact = false,
  }) {
    // Size adjustments for compact mode
    final fontSize = isCompact ? 6.0 : 8.0;
    final padding =
        isCompact
            ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
            : const EdgeInsets.symmetric(horizontal: 6, vertical: 3);
    final cornerRadius =
        isCompact ? const Radius.circular(6) : const Radius.circular(8);

    // Completed badge
    if (isCompleted || _progressPercentage >= 0.99) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.green[700],
          borderRadius: BorderRadius.only(bottomLeft: cornerRadius),
        ),
        child: Text(
          'COMPLETED',
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    // New badge
    if (isNew) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.yellow[800],
          borderRadius: BorderRadius.only(bottomLeft: cornerRadius),
        ),
        child: Text(
          'NEW',
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    // In progress badge
    if (hasProgress) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: colorScheme.primary,
          borderRadius: BorderRadius.only(bottomLeft: cornerRadius),
        ),
        child: Text(
          'IN PROGRESS',
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    // No badge
    return const SizedBox.shrink();
  }
}
