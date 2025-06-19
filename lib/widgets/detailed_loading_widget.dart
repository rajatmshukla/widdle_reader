import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import '../providers/audiobook_provider.dart';

class DetailedLoadingWidget extends StatefulWidget {
  const DetailedLoadingWidget({super.key});

  @override
  State<DetailedLoadingWidget> createState() => _DetailedLoadingWidgetState();
}

class _DetailedLoadingWidgetState extends State<DetailedLoadingWidget>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    
    return Consumer<AudiobookProvider>(
      builder: (context, provider, child) {
        // Show overlay when detailed loading is active
        if (!provider.isDetailedLoading) {
          return const SizedBox.shrink();
        }

        // Start animation when loading begins
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_fadeController.isCompleted) {
            _fadeController.forward();
          }
        });

        final progress = provider.loadingProgress;
        final progressPercent = (progress * 100).toInt();
        final currentFile = provider.currentLoadingFile;
        final processed = provider.filesProcessed;
        final total = provider.totalFilesToProcess;
        
        return Stack(
          children: [
            // Fullscreen overlay with blur
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _fadeAnimation,
                builder: (context, child) {
                  return Opacity(
                    opacity: _fadeAnimation.value,
                    child: Container(
                      width: size.width,
                      height: size.height,
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: colorScheme.surface.withOpacity(0.8),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            
            // Simplified loading card with fixed size
            Center(
              child: AnimatedBuilder(
                animation: _fadeAnimation,
                builder: (context, child) {
                  return Opacity(
                    opacity: _fadeAnimation.value,
                    child: Container(
                      width: size.width * 0.9,
                      constraints: const BoxConstraints(
                        maxWidth: 500,
                        // LARGER FIXED HEIGHT to prevent any text overflow
                        minHeight: 280,
                        maxHeight: 280,
                      ),
                      margin: const EdgeInsets.all(20),
                      padding: const EdgeInsets.all(32), // Increased padding
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: colorScheme.outline.withOpacity(0.2),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.shadow.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header with progress
                          Row(
                            children: [
                              SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  value: progress > 0 ? progress : null,
                                  valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                                ),
                              ),
                              const SizedBox(width: 20), // Increased spacing
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Adding Audiobooks',
                                      style: TextStyle(
                                        fontSize: 20, // Slightly larger
                                        fontWeight: FontWeight.w700,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 6), // Added spacing
                                    Text(
                                      '$processed of $total books ($progressPercent%)',
                                      style: TextStyle(
                                        fontSize: 15, // Slightly larger
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 30), // Increased spacing
                          
                          // Progress bar
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 10, // Slightly thicker
                              backgroundColor: colorScheme.surfaceVariant,
                              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                            ),
                          ),
                          
                          const SizedBox(height: 24), // Increased spacing
                          
                          // Current book name
                          if (currentFile.isNotEmpty) ...[
                            Text(
                              'Current Book:',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8), // Increased spacing
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), // Increased padding
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceVariant.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                currentFile,
                                style: TextStyle(
                                  fontSize: 14, // Slightly larger
                                  fontWeight: FontWeight.w500,
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.4, // Better line height
                                ),
                                maxLines: 3, // Allow more lines
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ] else ...[
                            // Placeholder to maintain consistent height when no current file
                            Text(
                              'Initializing...',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceVariant.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Preparing to scan audiobook folders...',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                                  height: 1.4,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
} 