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
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  bool _showCompletionDialog = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  void _showCompletion() {
    setState(() {
      _showCompletionDialog = true;
    });
    _scaleController.forward();
  }

  void _hideOverlay() {
    _fadeController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _showCompletionDialog = false;
        });
        _scaleController.reset();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    
    return Consumer<AudiobookProvider>(
      builder: (context, provider, child) {
        // Show overlay when detailed loading is active or completion dialog is shown
        final shouldShow = provider.isDetailedLoading || _showCompletionDialog;
        
        if (!shouldShow) {
          return const SizedBox.shrink();
        }

        // Start animations when loading begins
        if (provider.isDetailedLoading && !_showCompletionDialog) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _fadeController.forward();
            }
          });
        }

        // Check if loading just completed
        if (!provider.isDetailedLoading && !_showCompletionDialog && _fadeController.isCompleted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showCompletion();
            }
          });
        }

        final progress = provider.loadingProgress;
        final progressPercent = (progress * 100).toInt();
        
        return Stack(
          children: [
            // Fullscreen overlay with blur
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _fadeAnimation,
                builder: (context, child) {
                  return Opacity(
                    opacity: _fadeAnimation.value,
                    child: GestureDetector(
                      onTap: _showCompletionDialog ? _hideOverlay : null,
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
                    ),
                  );
                },
              ),
            ),
            
            // Main loading card
            if (!_showCompletionDialog)
              Center(
                child: AnimatedBuilder(
                  animation: _fadeAnimation,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _fadeAnimation.value,
                      child: Container(
                        width: size.width * 0.85,
                        constraints: BoxConstraints(
                          maxWidth: 500,
                          maxHeight: size.height * 0.8,
                          minHeight: 600, // Fixed minimum height
                        ),
                        margin: const EdgeInsets.all(20),
                        padding: const EdgeInsets.all(24),
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
                          mainAxisSize: MainAxisSize.max,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header with loading animation
                            Row(
                              children: [
                                SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Processing Audiobooks',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                      Text(
                                        'Real-time processing monitor',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    '$progressPercent%',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 20),
                            
                            // Progress bar with detailed info
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Overall Progress',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    Text(
                                      '${provider.filesProcessed} / ${provider.totalFilesToProcess} books',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    backgroundColor: colorScheme.outline.withOpacity(0.2),
                                    valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                                    minHeight: 8,
                                  ),
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 20),
                            
                            // Current processing info
                            if (provider.currentLoadingStep.isNotEmpty) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: colorScheme.primary.withOpacity(0.2),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.auto_awesome,
                                          size: 16,
                                          color: colorScheme.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Current Step',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: colorScheme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      provider.currentLoadingStep,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            
                            // Current file being processed (redesigned to match live processing style)
                            if (provider.currentLoadingFile.isNotEmpty) ...[
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.auto_fix_high,
                                        size: 16,
                                        color: colorScheme.tertiary,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Current Task',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.tertiary,
                                        ),
                                      ),
                                      const Spacer(),
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(colorScheme.tertiary),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    height: 80, // Fixed height container
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainer.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: colorScheme.outline.withOpacity(0.2),
                                        width: 1,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        // Current step
                                        Text(
                                          provider.currentLoadingStep,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: colorScheme.onSurface,
                                            fontFamily: 'monospace',
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 6),
                                        // Current file with icon
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.folder_outlined,
                                              size: 14,
                                              color: colorScheme.tertiary,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                provider.currentLoadingFile,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: colorScheme.onSurfaceVariant,
                                                  fontFamily: 'monospace',
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],
                            
                            // Live Activity Log
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.timeline,
                                        size: 16,
                                        color: colorScheme.secondary,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Live Activity Monitor',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.secondary,
                                        ),
                                      ),
                                      const Spacer(),
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: colorScheme.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'LIVE',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: colorScheme.surfaceContainer.withOpacity(0.5),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: colorScheme.outline.withOpacity(0.2),
                                          width: 1,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          // Activity log
                                          Expanded(
                                            flex: 3,
                                            child: Container(
                                              width: double.infinity,
                                              child: SingleChildScrollView(
                                                reverse: true, // Always show latest activities
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    if (provider.activityLog.isEmpty)
                                                      Text(
                                                        'Initializing...',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                                                          fontFamily: 'monospace',
                                                        ),
                                                      )
                                                    else
                                                      ...provider.activityLog.map((activity) => Padding(
                                                        padding: const EdgeInsets.only(bottom: 4),
                                                        child: Text(
                                                          activity,
                                                          style: TextStyle(
                                                                                                                         fontSize: 11,
                                                             color: colorScheme.onSurface,
                                                             fontFamily: 'monospace',
                                                             height: 1.3,
                                                           ),
                                                        ),
                                                      )),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          
                                          // Separator
                                          Container(
                                            margin: const EdgeInsets.symmetric(vertical: 8),
                                            height: 1,
                                            color: colorScheme.outline.withOpacity(0.2),
                                          ),
                                          
                                          // Detailed statistics
                                          Expanded(
                                            flex: 2,
                                            child: Container(
                                              width: double.infinity,
                                              child: SingleChildScrollView(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Icons.analytics_outlined,
                                                          size: 12,
                                                          color: colorScheme.tertiary,
                                                        ),
                                                        const SizedBox(width: 6),
                                                        Text(
                                                          'Statistics',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w600,
                                                            color: colorScheme.tertiary,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 6),
                                                    if (provider.detailedStats.isEmpty)
                                                      Text(
                                                        'Gathering data...',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                                                          fontFamily: 'monospace',
                                                        ),
                                                      )
                                                    else
                                                      ...provider.detailedStats.map((stat) => Padding(
                                                        padding: const EdgeInsets.only(bottom: 3),
                                                        child: Text(
                                                          '• $stat',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: colorScheme.onSurfaceVariant,
                                                            fontFamily: 'monospace',
                                                            height: 1.2,
                                                          ),
                                                        ),
                                                      )),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Processing info footer
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: 14,
                                    color: colorScheme.secondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Processing includes metadata extraction, cover art analysis, chapter organization, and library indexing.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            
            // Completion dialog
            if (_showCompletionDialog)
              Center(
                child: AnimatedBuilder(
                  animation: _scaleAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _scaleAnimation.value,
                      child: GestureDetector(
                        onTap: _hideOverlay,
                        child: Container(
                          width: size.width * 0.8,
                          constraints: const BoxConstraints(maxWidth: 400),
                          margin: const EdgeInsets.all(20),
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: colorScheme.primary.withOpacity(0.3),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.shadow.withOpacity(0.3),
                                blurRadius: 30,
                                offset: const Offset(0, 15),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Success icon
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.check_circle,
                                  size: 36,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 20),
                              
                              // Title
                              Text(
                                'Processing Complete!',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onSurface,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              
                              // Message
                              Text(
                                'Your audiobooks have been successfully processed and added to your library.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                              
                              // Complete button
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: _hideOverlay,
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'Complete',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              
                              // Tap anywhere hint
                              Text(
                                'Tap anywhere to continue',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
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