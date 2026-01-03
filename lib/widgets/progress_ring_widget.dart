import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Animated circular progress ring showing reading progress
/// Animated circular progress ring showing reading progress
class ProgressRingWidget extends StatefulWidget {
  final int currentMinutes;
  final int currentSeconds; // Optional precise tracking
  final int targetMinutes;
  final String metricLabel;
  final VoidCallback? onTap;

  const ProgressRingWidget({
    super.key,
    this.currentMinutes = 0,
    this.currentSeconds = 0,
    required this.targetMinutes,
    this.metricLabel = 'Today',
    this.onTap,
    this.showHoursMode = false,
  });

  final bool showHoursMode;

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
        oldWidget.currentSeconds != widget.currentSeconds ||
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
    
    // Use seconds if available for smoother progress
    if (widget.currentSeconds > 0) {
      return (widget.currentSeconds / (widget.targetMinutes * 60)).clamp(0.0, 1.5);
    }
    
    return (widget.currentMinutes / widget.targetMinutes).clamp(0.0, 1.5);
  }

  Color _getProgressColor(BuildContext context, double progress) {
    final colorScheme = Theme.of(context).colorScheme;
    // Always use primary (seed) color - vary opacity based on progress
    if (progress >= 1.0) {
      return colorScheme.primary; // Full opacity for completion
    } else {
      // Slightly desaturated at low progress, full saturation at higher progress
      return colorScheme.primary.withOpacity(0.7 + (0.3 * progress));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Determine display values
    String displayValue;
    String displayUnit;

    final totalMinutes = widget.currentSeconds > 0 
        ? (widget.currentSeconds / 60).round()
        : widget.currentMinutes;

    if (widget.showHoursMode && totalMinutes >= 60) {
      final hours = totalMinutes ~/ 60;
      final minutes = totalMinutes % 60;
      
      if (minutes == 0) {
        displayValue = '$hours';
        displayUnit = hours == 1 ? 'hour' : 'hours';
      } else {
        displayValue = '${hours}h ${minutes}m';
        displayUnit = ''; // Unit already included in displayValue
      }
    } else if (widget.currentSeconds > 0 && widget.currentSeconds < 60) {
      displayValue = '${widget.currentSeconds}';
      displayUnit = 'seconds';
    } else {
      displayValue = '$totalMinutes';
      displayUnit = 'minutes';
    }

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
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.metricLabel.toUpperCase(),
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.5),
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            displayUnit.isEmpty ? displayValue : displayValue,
                            style: textTheme.displayLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: progressColor,
                              fontSize: 40,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        if (displayUnit.isNotEmpty)
                          Text(
                            displayUnit,
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        const SizedBox(height: 8),
                        // Goal reached or Total Goal
                        if (progress >= 1.0)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('🔥', style: const TextStyle(fontSize: 14)),
                              const SizedBox(width: 4),
                              Text(
                                'GOAL REACHED',
                                style: TextStyle(
                                  color: progressColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          )
                        else if (widget.targetMinutes > 0)
                          Text(
                            'GOAL: ${widget.targetMinutes}m',
                            style: textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant.withOpacity(0.8),
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
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
