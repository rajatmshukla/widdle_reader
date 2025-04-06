import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/app_logo.dart';
// Assuming this path is correct

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000), // Longer animation
      vsync: this,
    );

    // Fade in animation
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    // Bounce scale animation
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.7,
          end: 1.1,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.1,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.elasticIn)),
        weight: 40,
      ),
    ]).animate(_controller);

    _controller.forward(); // Start animations

    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        // Check if widget is still in the tree
        Navigator.pushReplacementNamed(context, '/library');
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
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        // Use gradient background
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [colorScheme.primaryContainer, colorScheme.surface],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: AppLogo(size: 150, showTitle: true, animate: true),
            ),
          ),
        ),
      ),
    );
  }
}
