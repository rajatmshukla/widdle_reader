import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Snowflake data class for animation
class Snowflake {
  late double x;           // Horizontal position (0-1000)
  late double initialY;    // Starting vertical position (off-screen)
  late double size;        // 10-30px
  late double opacity;     // 0.1-0.5
  late double rotationSpeed; // -1 to 1 (random rotation)

  Snowflake(Random random) {
    x = random.nextDouble() * 1000;
    initialY = random.nextDouble() * 1000 - 1000;
    size = random.nextDouble() * 20 + 10;
    opacity = random.nextDouble() * 0.4 + 0.1;
    rotationSpeed = random.nextDouble() * 2 - 1;
  }
}

/// A festive splash screen that appears during the holiday season (Dec 23 – Jan 4).
/// Features a winter night theme with falling snowflakes and automatically 
/// navigates to the main app after 4 seconds.
class HolidaySplashScreen extends StatefulWidget {
  final VoidCallback onComplete; // Callback to navigate away

  const HolidaySplashScreen({
    super.key,
    required this.onComplete,
  });

  @override
  State<HolidaySplashScreen> createState() => _HolidaySplashScreenState();
}

class _HolidaySplashScreenState extends State<HolidaySplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late List<Snowflake> _snowflakes;
  Timer? _timer;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();

    // Create 50 random snowflakes
    _snowflakes = List.generate(50, (index) => Snowflake(_random));

    // Start animation loop (10-second cycle)
    _controller = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();

    // Navigate after 4 seconds
    _timer = Timer(const Duration(seconds: 4), _safeNavigate);
  }

  void _safeNavigate() {
    if (!mounted) return; // Guard against disposed widget
    try {
      _timer?.cancel();
      widget.onComplete(); // Call the callback
    } catch (e) {
      debugPrint("Navigation error: $e");
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // Layer 1: Deep midnight blue gradient background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0A1628), // Deep midnight blue
                  Color(0xFF1A2A4A), // Slightly lighter blue
                  Color(0xFF2D3E60), // Even lighter at bottom
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // Layer 2: Subtle moon glow effect at top
          Positioned(
            top: -100,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.2),
                    Colors.white.withValues(alpha: 0.1),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),
          ),

          // Layer 3: Falling snowflakes
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Stack(
                children: _snowflakes.map((snowflake) {
                  // Calculate Y position based on animation value
                  final animProgress = _controller.value;
                  final yOffset = animProgress * 2000; // Fall distance
                  final currentY = (snowflake.initialY + yOffset) % screenSize.height;
                  
                  // Calculate X position with slight horizontal drift
                  final xDrift = sin(animProgress * pi * 2 + snowflake.x) * 20;
                  final currentX = (snowflake.x / 1000 * screenSize.width) + xDrift;

                  // Calculate rotation
                  final rotation = animProgress * snowflake.rotationSpeed * 2 * pi;

                  return Positioned(
                    left: currentX,
                    top: currentY,
                    child: Transform.rotate(
                      angle: rotation,
                      child: Icon(
                        Icons.ac_unit,
                        size: snowflake.size,
                        color: Colors.white.withValues(alpha: snowflake.opacity),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),

          // Layer 4: Snow ground at bottom with curved top
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.elliptical(200, 60),
                  topRight: Radius.elliptical(200, 60),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, -10),
                  ),
                ],
              ),
            ),
          ),

          // Layer 5: Main content - logo, greeting, and button
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Holiday logo
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset(
                      'assets/icons/app_logo_holidays.png',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        // Fallback to regular logo if holiday logo not found
                        return Image.asset(
                          'assets/icons/app_logo_holidays.png',
                          fit: BoxFit.cover,
                        );
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // "Merry Christmas" text with festive font
                Text(
                  'Merry Christmas',
                  style: GoogleFonts.mountainsOfChristmas(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Subtitle
                Text(
                  '& Happy New Year!',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withValues(alpha: 0.7),
                    letterSpacing: 1.2,
                  ),
                ),

                const SizedBox(height: 48),

                // Continue button
                GestureDetector(
                  onTap: _safeNavigate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF2E7D32), // Dark green
                          Color(0xFF4CAF50), // Light green
                        ],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2E7D32).withValues(alpha: 0.4),
                          blurRadius: 15,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Continue',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Layer 6: Bottom branding
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  'Widdle Reader',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A2A4A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Spreading joy, one story at a time',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF1A2A4A).withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
