import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../models/achievement.dart';

/// Animated achievement badge with unlock animation
class AchievementBadge extends StatefulWidget {
  final Achievement achievement;
  final double size;
  final bool showLabel;
  final bool animate;
  final VoidCallback? onTap;

  const AchievementBadge({
    super.key,
    required this.achievement,
    this.size = 80,
    this.showLabel = true,
    this.animate = false,
    this.onTap,
  });

  @override
  State<AchievementBadge> createState() => _AchievementBadgeState();
}

class _AchievementBadgeState extends State<AchievementBadge>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _shimmerController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.2), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 0.9), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 40),
    ]).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeOut,
    ));

    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    if (widget.animate) {
      _scaleController.forward();
      _shimmerController.repeat();
    } else {
      _scaleController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final achievement = widget.achievement;
    final isUnlocked = achievement.isUnlocked;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([_scaleAnimation, _shimmerAnimation]),
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Badge circle
                Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isUnlocked
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              achievement.tierColor,
                              achievement.tierColor.withOpacity(0.7),
                            ],
                          )
                        : null,
                    color: isUnlocked ? null : colorScheme.surfaceContainerHigh,
                    boxShadow: isUnlocked
                        ? [
                            BoxShadow(
                              color: achievement.tierColor.withOpacity(0.4),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Icon
                      Icon(
                        isUnlocked ? achievement.icon : Icons.lock,
                        size: widget.size * 0.45,
                        color: isUnlocked
                            ? Colors.white
                            : colorScheme.onSurfaceVariant.withOpacity(0.5),
                      ),
                      // Shimmer effect for unlocked badges
                      if (isUnlocked && widget.animate)
                        Positioned.fill(
                          child: ClipOval(
                            child: CustomPaint(
                              painter: _ShimmerPainter(
                                progress: _shimmerAnimation.value,
                                color: Colors.white.withOpacity(0.3),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Label
                if (widget.showLabel) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: widget.size + 20,
                    child: Text(
                      isUnlocked || !achievement.isSecret
                          ? achievement.name
                          : '???',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: isUnlocked
                                ? colorScheme.onSurface
                                : colorScheme.onSurfaceVariant,
                            fontWeight:
                                isUnlocked ? FontWeight.w600 : FontWeight.normal,
                          ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Shimmer effect painter
class _ShimmerPainter extends CustomPainter {
  final double progress;
  final Color color;

  _ShimmerPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.transparent,
          color,
          Colors.transparent,
        ],
        stops: [
          (progress - 0.3).clamp(0.0, 1.0),
          progress.clamp(0.0, 1.0),
          (progress + 0.3).clamp(0.0, 1.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_ShimmerPainter oldDelegate) {
    return progress != oldDelegate.progress;
  }
}

/// Achievement unlock notification dialog
class AchievementUnlockDialog extends StatefulWidget {
  final Achievement achievement;

  const AchievementUnlockDialog({super.key, required this.achievement});

  @override
  State<AchievementUnlockDialog> createState() => _AchievementUnlockDialogState();
}

class _AchievementUnlockDialogState extends State<AchievementUnlockDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.5, end: 1.1), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0), weight: 40),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: AlertDialog(
              backgroundColor: colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Celebration text
                  Text(
                    '🎉 Achievement Unlocked!',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Badge
                  AchievementBadge(
                    achievement: widget.achievement,
                    size: 100,
                    showLabel: false,
                    animate: true,
                  ),
                  const SizedBox(height: 16),
                  // Name
                  Text(
                    widget.achievement.name,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Description
                  Text(
                    widget.achievement.description,
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Tier badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: widget.achievement.tierColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      widget.achievement.tier.displayName,
                      style: textTheme.labelSmall?.copyWith(
                        color: widget.achievement.tierColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Awesome!'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
