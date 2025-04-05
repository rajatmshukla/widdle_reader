import 'package:flutter/material.dart';
import 'dart:math' as math;

/// A cute custom loading widget with animations
class CuteLoading extends StatefulWidget {
  /// The size of the loading widget
  final double size;

  /// The color of the loading widget (will be used with opacity variations)
  final Color? color;

  /// Optional message to display below the animation
  final String? message;

  const CuteLoading({super.key, this.size = 100.0, this.color, this.message});

  @override
  State<CuteLoading> createState() => _CuteLoadingState();
}

class _CuteLoadingState extends State<CuteLoading>
    with TickerProviderStateMixin {
  late AnimationController _bounceController;
  late AnimationController _rotateController;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();

    // Setup the bounce animation
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Setup the rotation animation
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    // Create a bouncing effect using a custom Tween
    _bounceAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 0.7,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.7,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
    ]).animate(_bounceController);

    // Start both animations
    _bounceController.repeat();
    _rotateController.repeat();
  }

  @override
  void dispose() {
    _bounceController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color loadingColor = widget.color ?? theme.colorScheme.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The animated loading indicator
        AnimatedBuilder(
          animation: Listenable.merge([_bounceController, _rotateController]),
          builder: (context, child) {
            return Transform.rotate(
              angle: _rotateController.value * 2 * math.pi,
              child: ScaleTransition(
                scale: _bounceAnimation,
                child: _buildLoadingShape(loadingColor),
              ),
            );
          },
        ),

        // Optional message text
        if (widget.message != null) ...[
          const SizedBox(height: 24),
          Text(
            widget.message!,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildLoadingShape(Color color) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        children: [
          // Center circle
          Center(
            child: Container(
              width: widget.size * 0.35,
              height: widget.size * 0.35,
              decoration: BoxDecoration(
                color: color.withOpacity(0.9),
                shape: BoxShape.circle,
              ),
            ),
          ),

          // Outer circles that appear to be orbiting
          ...List.generate(4, (index) {
            final double angle = index * (math.pi / 2);
            final double offsetValue = widget.size * 0.35;

            return Positioned(
              left:
                  (widget.size / 2) +
                  offsetValue * math.cos(angle) -
                  (widget.size * 0.15),
              top:
                  (widget.size / 2) +
                  offsetValue * math.sin(angle) -
                  (widget.size * 0.15),
              child: Container(
                width: widget.size * 0.3,
                height: widget.size * 0.3,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.5 + (index * 0.1)),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),

          // Music note icon in the center
          Center(
            child: Icon(
              Icons.music_note_rounded,
              color: Colors.white,
              size: widget.size * 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// A cute, animated loading overlay for the entire screen
class CuteLoadingOverlay extends StatelessWidget {
  /// Whether to show the overlay
  final bool isLoading;

  /// Optional message to display
  final String? message;

  /// Widget to display when not loading
  final Widget child;

  const CuteLoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main content
        child,

        // Loading overlay with animation
        if (isLoading)
          Container(
            color: Colors.black.withOpacity(0.7),
            width: double.infinity,
            height: double.infinity,
            child: Center(
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: CuteLoading(message: message ?? 'Loading...'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
