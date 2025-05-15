import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/app_logo.dart';
import '../utils/responsive_utils.dart';

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
      duration: const Duration(milliseconds: 2000), // Animation duration
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
    final isLandscape = ResponsiveUtils.isLandscape(context);

    // Calculate logo size based on orientation
    final double logoSize =
        isLandscape ? MediaQuery.of(context).size.height * 0.4 : 150;

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
          child:
              isLandscape
                  ? _buildLandscapeSplash(logoSize, colorScheme)
                  : _buildPortraitSplash(logoSize, colorScheme),
        ),
      ),
    );
  }

  Widget _buildPortraitSplash(double logoSize, ColorScheme colorScheme) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AppLogo(size: logoSize, showTitle: true, animate: true),
      ),
    );
  }

  Widget _buildLandscapeSplash(double logoSize, ColorScheme colorScheme) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo on the left
          ScaleTransition(
            scale: _scaleAnimation,
            child: AppLogo(size: logoSize, showTitle: false, animate: true),
          ),
          const SizedBox(width: 32),
          // Text on the right
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Widdle Reader',
                style: TextStyle(
                  fontSize: logoSize * 0.25,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              SizedBox(height: logoSize * 0.05),
              Text(
                'Your cute audiobook companion',
                style: TextStyle(
                  fontSize: logoSize * 0.1,
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
