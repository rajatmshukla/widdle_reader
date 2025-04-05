import 'dart:async';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500), // Fade duration
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    _controller.forward(); // Start fade in

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
    return Scaffold(
      backgroundColor: Colors.grey[900], // Dark theme background
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.menu_book, // Book icon
                size: 100.0,
                color: Colors.tealAccent[100], // A modern accent color
              ),
              const SizedBox(height: 20),
              Text(
                'Widdle Reader',
                style: TextStyle(
                  fontSize: 28.0,
                  fontWeight: FontWeight.w300, // Sleek font weight
                  color: Colors.white,
                  fontFamily:
                      'Roboto', // Example modern font (ensure it's added if custom)
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
