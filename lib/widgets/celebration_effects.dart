import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Celebration particle effect widget
class CelebrationParticles extends StatefulWidget {
  final bool play;
  final Color? primaryColor;
  final VoidCallback? onComplete;

  const CelebrationParticles({
    super.key,
    this.play = false,
    this.primaryColor,
    this.onComplete,
  });

  @override
  State<CelebrationParticles> createState() => _CelebrationParticlesState();
}

class _CelebrationParticlesState extends State<CelebrationParticles>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_Particle> _particles = [];
  final math.Random _random = math.Random();

  static const int particleCount = 50;
  static const List<Color> defaultColors = [
    Color(0xFFFF6B6B),
    Color(0xFF4ECDC4),
    Color(0xFFFFE66D),
    Color(0xFF95E1D3),
    Color(0xFFF38181),
    Color(0xFFAA96DA),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete?.call();
      }
    });

    if (widget.play) {
      _startAnimation();
    }
  }

  @override
  void didUpdateWidget(CelebrationParticles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.play && !oldWidget.play) {
      _startAnimation();
    }
  }

  void _startAnimation() {
    _generateParticles();
    _controller.forward(from: 0);
  }

  void _generateParticles() {
    _particles.clear();
    final colors = widget.primaryColor != null
        ? [widget.primaryColor!, ...defaultColors]
        : defaultColors;

    for (int i = 0; i < particleCount; i++) {
      _particles.add(_Particle(
        x: 0.5, // Start from center
        y: 0.5,
        velocityX: (_random.nextDouble() - 0.5) * 2,
        velocityY: -_random.nextDouble() * 1.5 - 0.5,
        size: _random.nextDouble() * 8 + 4,
        color: colors[_random.nextInt(colors.length)],
        rotation: _random.nextDouble() * math.pi * 2,
        rotationSpeed: (_random.nextDouble() - 0.5) * 10,
        shape: _ParticleShape.values[_random.nextInt(_ParticleShape.values.length)],
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _ParticlePainter(
            particles: _particles,
            progress: _controller.value,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _Particle {
  double x;
  double y;
  final double velocityX;
  final double velocityY;
  final double size;
  final Color color;
  double rotation;
  final double rotationSpeed;
  final _ParticleShape shape;

  _Particle({
    required this.x,
    required this.y,
    required this.velocityX,
    required this.velocityY,
    required this.size,
    required this.color,
    required this.rotation,
    required this.rotationSpeed,
    required this.shape,
  });
}

enum _ParticleShape { circle, square, star }

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;

  _ParticlePainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      // Update position with physics
      final gravity = 0.5;
      final time = progress;
      final x = size.width * (particle.x + particle.velocityX * time);
      final y = size.height * (particle.y + particle.velocityY * time + gravity * time * time);
      final rotation = particle.rotation + particle.rotationSpeed * time;

      // Fade out
      final opacity = (1 - progress).clamp(0.0, 1.0);

      // Skip if off screen
      if (x < -50 || x > size.width + 50 || y < -50 || y > size.height + 50) {
        continue;
      }

      final paint = Paint()
        ..color = particle.color.withOpacity(opacity)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);

      switch (particle.shape) {
        case _ParticleShape.circle:
          canvas.drawCircle(Offset.zero, particle.size / 2, paint);
          break;
        case _ParticleShape.square:
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset.zero,
              width: particle.size,
              height: particle.size,
            ),
            paint,
          );
          break;
        case _ParticleShape.star:
          _drawStar(canvas, particle.size / 2, paint);
          break;
      }

      canvas.restore();
    }
  }

  void _drawStar(Canvas canvas, double radius, Paint paint) {
    final path = Path();
    final outerRadius = radius;
    final innerRadius = radius * 0.4;

    for (int i = 0; i < 5; i++) {
      final outerAngle = (i * 4 * math.pi / 5) - math.pi / 2;
      final innerAngle = outerAngle + 2 * math.pi / 10;

      final outerX = outerRadius * math.cos(outerAngle);
      final outerY = outerRadius * math.sin(outerAngle);
      final innerX = innerRadius * math.cos(innerAngle);
      final innerY = innerRadius * math.sin(innerAngle);

      if (i == 0) {
        path.moveTo(outerX, outerY);
      } else {
        path.lineTo(outerX, outerY);
      }
      path.lineTo(innerX, innerY);
    }
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ParticlePainter oldDelegate) {
    return progress != oldDelegate.progress;
  }
}

/// Confetti burst effect for achievements
class ConfettiBurst extends StatefulWidget {
  final bool trigger;
  final Widget child;

  const ConfettiBurst({
    super.key,
    this.trigger = false,
    required this.child,
  });

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst> {
  bool _showParticles = false;

  @override
  void didUpdateWidget(ConfettiBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger && !oldWidget.trigger) {
      setState(() => _showParticles = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_showParticles)
          Positioned.fill(
            child: IgnorePointer(
              child: CelebrationParticles(
                play: true,
                primaryColor: Theme.of(context).colorScheme.primary,
                onComplete: () {
                  if (mounted) {
                    setState(() => _showParticles = false);
                  }
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// Pulse animation for achievement unlocks
class PulseAnimation extends StatefulWidget {
  final Widget child;
  final bool animate;
  final Duration duration;

  const PulseAnimation({
    super.key,
    required this.child,
    this.animate = true,
    this.duration = const Duration(milliseconds: 1000),
  });

  @override
  State<PulseAnimation> createState() => _PulseAnimationState();
}

class _PulseAnimationState extends State<PulseAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _animation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.animate) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(PulseAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate != oldWidget.animate) {
      if (widget.animate) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.scale(
          scale: _animation.value,
          child: widget.child,
        );
      },
    );
  }
}
