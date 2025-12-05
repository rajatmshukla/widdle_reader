import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Animated circular progress ring showing reading progress
class ProgressRingWidget extends StatefulWidget {
  final int currentMinutes;
  final int targetMinutes;
  final String metricLabel;
  final VoidCallback? onTap;

  const ProgressRingWidget({
    super.key,
    required this.currentMinutes,
    required this.targetMinutes,
    this.metricLabel = 'Today',
    this.onTap,
  });

  @override
  State<ProgressRingWidget> createState() => _ProgressRingWidgetState();
}

class _ProgressRingWidgetState extends State<ProgressRingWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progressAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _progressAnimation = Tween<double>(
      begin: 0.0,
      end: _getProgressValue(),
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    ));

    _controller.forward();
  }

  @override
  void didUpdateWidget(ProgressRingWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentMinutes != widget.currentMinutes ||
        oldWidget.targetMinutes != widget.targetMinutes) {
      _progressAnimation = Tween<double>(
        begin: _progressAnimation.value,
        end: _getProgressValue(),
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ));
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _getProgressValue() {
    if (widget.targetMinutes == 0) return 0.0;
    return (widget.currentMinutes / widget.targetMinutes).clamp(0.0, 1.5);
  }

  Color _getProgressColor(BuildContext context, double progress) {
    final colorScheme = Theme.of(context).colorScheme;
    if (progress >= 1.0) {
      return colorScheme.primary; // Theme primary color for completion
    } else {
      // Gradient from tertiary to primary based on progress
      return Color.lerp(
        colorScheme.tertiary,
        colorScheme.primary,
        progress,
      )!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final progress = _progressAnimation.value;
          final progressColor = _getProgressColor(context, progress);

          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: progress >= 1.0
                    ? [
                        BoxShadow(
                          color: progressColor.withOpacity(0.4),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ]
                    : [],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Background circle
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: CustomPaint(
                      painter: _RingPainter(
                        progress: progress,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        progressColor: progressColor,
                        strokeWidth: 16,
                      ),
                    ),
                  ),
                  // Center content
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${widget.currentMinutes}',
                        style: textTheme.displayLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: progressColor,
                          fontSize: 56,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'minutes',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.metricLabel,
                        style: textTheme.labelLarge?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                      if (widget.targetMinutes > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Goal: ${widget.targetMinutes}min',
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                  // Achievement indicator - Moved to bottom and integrated
                  if (progress >= 1.0)
                    Positioned(
                      bottom: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: progressColor,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: progressColor.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '🔥',
                              style: TextStyle(fontSize: 16),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Goal Reached!',
                              style: TextStyle(
                                color: colorScheme.onPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color backgroundColor;
  final Color progressColor;
  final double strokeWidth;

  _RingPainter({
    required this.progress,
    required this.backgroundColor,
    required this.progressColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background arc
    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, backgroundPaint);

    // Progress arc with gradient
    if (progress > 0) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      // Use a simpler gradient based on the single progress color
      final gradient = SweepGradient(
        colors: [
          progressColor.withOpacity(0.5),
          progressColor,
        ],
        stops: const [0.0, 1.0],
        startAngle: -math.pi / 2,
        endAngle: -math.pi / 2 + (2 * math.pi * progress.clamp(0.0, 1.0)),
      );

      final progressPaint = Paint()
        ..shader = gradient.createShader(rect)
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final sweepAngle = 2 * math.pi * progress.clamp(0.0, 1.0);
      canvas.drawArc(
        rect,
        -math.pi / 2, // Start from top
        sweepAngle,
        false,
        progressPaint,
      );

      // Glow effect for completed
      if (progress >= 1.0) {
        final glowPaint = Paint()
          ..color = progressColor.withOpacity(0.2)
          ..strokeWidth = strokeWidth + 4
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

        canvas.drawArc(
          rect,
          -math.pi / 2,
          sweepAngle,
          false,
          glowPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.progressColor != progressColor;
  }
}
