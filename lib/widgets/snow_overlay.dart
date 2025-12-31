
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';

// Global provider for snow effect
// Global provider for snow effect
final snowProvider = StateNotifierProvider<SnowNotifier, bool>((ref) {
  return SnowNotifier();
});

class SnowNotifier extends StateNotifier<bool> {
  SnowNotifier() : super(false) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('snow_effect_enabled') ?? false;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('snow_effect_enabled', state);
  }
}

class SnowOverlay extends ConsumerStatefulWidget {
  const SnowOverlay({super.key});

  @override
  ConsumerState<SnowOverlay> createState() => _SnowOverlayState();
}

class _SnowOverlayState extends ConsumerState<SnowOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Snowflake> _snowflakes = [];
  final int _snowflakeCount = 200; // Increased density for better "atmosphere"
  final Random _random = Random();
  double _time = 0;

  @override
  void initState() {
    super.initState();
    // Use a longer duration for the loop to have a smooth continuous time
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
    
    _controller.addListener(_updateSnowflakes);
    
    // Initialize snowflakes
    for (int i = 0; i < _snowflakeCount; i++) {
      _snowflakes.add(_createSnowflake());
    }
  }
  
  Snowflake _createSnowflake({bool startAtTop = false}) {
    // Google Studio style: Small, delicate, slightly varied fall speeds but mostly uniform
    return Snowflake(
      x: _random.nextDouble(), // 0.0 to 1.0
      y: startAtTop ? -0.05 : _random.nextDouble(),
      // Smaller size: 1.0 to 3.0 px
      size: _random.nextDouble() * 2.0 + 1.0, 
      // Slower, more graceful speed: 0.001 to 0.003 screen-heights per tick
      speed: _random.nextDouble() * 0.002 + 0.001, 
      // Gentle individual variation
      phase: _random.nextDouble() * 2 * pi,
      // Less chaotic wobble
      swaySpeed: _random.nextDouble() * 0.02 + 0.01, 
    );
  }

  void _updateSnowflakes() {
    // Only animate if snowing is enabled
    if (!ref.read(snowProvider)) return;
    
    // Global time from controller
    _time += 0.01;

    setState(() {
      for (final flake in _snowflakes) {
        // Vertical movement
        flake.y += flake.speed;
        
        // Horizontal movement:
        // 1. Global gentle wind (synchronized)
        double wind = sin(_time * 0.5) * 0.0005; 
        
        // 2. Individual sway (unsynchronized but smooth)
        double sway = sin(flake.phase + _time * flake.swaySpeed) * 0.001;
        
        flake.x += wind + sway;
        
        // Wrap around horizontally
        if (flake.x > 1.0) flake.x -= 1.0;
        if (flake.x < 0.0) flake.x += 1.0;

        // Reset if off bottom of screen
        if (flake.y > 1.05) {
          final newFlake = _createSnowflake(startAtTop: true);
          flake.y = newFlake.y;
          flake.x = _random.nextDouble(); // Randomize x entry
          flake.speed = newFlake.speed;
          flake.size = newFlake.size;
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSnowing = ref.watch(snowProvider);
    
    if (!isSnowing) return const SizedBox.shrink();

    return IgnorePointer(
      child: CustomPaint(
        painter: SnowPainter(_snowflakes),
        size: Size.infinite,
      ),
    );
  }
}

class Snowflake {
  double x;
  double y;
  double size;
  double speed;
  double phase;
  double swaySpeed;

  Snowflake({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.phase,
    required this.swaySpeed,
  });
}

class SnowPainter extends CustomPainter {
  final List<Snowflake> snowflakes;

  SnowPainter(this.snowflakes);

  @override
  void paint(Canvas canvas, Size size) {
    // Use a soft white, slightly transparent for "delicate" feel
    final paint = Paint()..color = Colors.white.withOpacity(0.65);
    
    for (final flake in snowflakes) {
      final dx = flake.x * size.width;
      final dy = flake.y * size.height;
      
      canvas.drawCircle(Offset(dx, dy), flake.size / 2, paint);
    }
  }

  @override
  bool shouldRepaint(SnowPainter oldDelegate) => true;
}
