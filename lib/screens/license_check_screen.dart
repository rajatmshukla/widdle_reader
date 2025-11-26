import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/license_service.dart';
import '../theme.dart';
import '../widgets/app_logo.dart';

class LicenseCheckScreen extends StatefulWidget {
  const LicenseCheckScreen({super.key});

  @override
  State<LicenseCheckScreen> createState() => _LicenseCheckScreenState();
}

class _LicenseCheckScreenState extends State<LicenseCheckScreen> with SingleTickerProviderStateMixin {
  bool _isChecking = true;
  bool _hasError = false;
  String _errorMessage = '';
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  Timer? _retryTimer;
  int _retryCount = 0;
  static const int _maxRetries = 3;
  
  @override
  void initState() {
    super.initState();
    
    // Set up animations
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    
    // Add bounce scale animation similar to splash screen
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
    ]).animate(_animationController);
    
    _animationController.forward();
    
    // Check the license on first load
    _checkLicense();
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    _retryTimer?.cancel();
    super.dispose();
  }
  
  // Check the Google Play license
  Future<void> _checkLicense() async {
    setState(() {
      _isChecking = true;
      _hasError = false;
      _errorMessage = '';
    });
    
    try {
      // CRITICAL FIX: Increased timeouts to prevent false failures
      await LicenseService.initialize().timeout(
        const Duration(seconds: 5), // Increased from 1s to 5s
        onTimeout: () => throw TimeoutException('License service timeout'),
      );
      
      final isLicensed = await LicenseService.isLicenseValid().timeout(
        const Duration(seconds: 5), // Increased from 800ms to 5s
        onTimeout: () => throw TimeoutException('License check timeout'),
      );
      
      if (isLicensed) {
        // License is valid, go directly to library - bypass splash screen
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/library');
        }
      } else {
        // Not licensed - show the purchase screen
        setState(() {
          _isChecking = false;
          _hasError = true;
          _errorMessage = 'This app requires a valid purchase from Google Play Store.';
        });
      }
    } catch (e) {
      // Error occurred during license check
      if (_retryCount < _maxRetries) {
        // Retry with much shorter delays for faster startup
        _retryCount++;
        final delayMilliseconds = _retryCount * 300; // 300ms, 600ms, 900ms
        
        setState(() {
          _isChecking = true;
          _errorMessage = 'Verifying purchase... Retrying in ${(delayMilliseconds/1000).toStringAsFixed(1)}s.';
        });
        
        _retryTimer = Timer(Duration(milliseconds: delayMilliseconds), _checkLicense);
      } else {
        // Max retries reached, show persistent error
        setState(() {
          _isChecking = false;
          _hasError = true;
          _errorMessage = 'Unable to verify purchase. Please ensure you\'re connected to the internet and try again.';
        });
      }
    }
  }
  
  // Launch Google Play Store
  Future<void> _launchGooglePlay() async {
    final Uri googlePlayUrl = Uri.parse(
      'https://play.google.com/store/apps/details?id=com.widdlereader.app'
    );
    
    if (await canLaunchUrl(googlePlayUrl)) {
      await launchUrl(googlePlayUrl, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open Google Play Store'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      body: Container(
        decoration: AppTheme.gradientBackground(context),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Replace the generic icon with animated AppLogo widget
                    ScaleTransition(
                      scale: _scaleAnimation,
                      child: AppLogo(
                        size: 120,
                        showTitle: false,
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // App name
                    Text(
                      'Widdle Reader',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onBackground,
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    // Tagline
                    Text(
                      'Your Premium Audiobook Player',
                      style: TextStyle(
                        fontSize: 16,
                        color: colorScheme.onBackground.withOpacity(0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),
                    
                    // License status area
                    if (_isChecking)
                      Column(
                        children: [
                          CircularProgressIndicator(
                            color: colorScheme.primary,
                            strokeWidth: 3,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Verifying purchase...',
                            style: TextStyle(
                              fontSize: 16,
                              color: colorScheme.onBackground,
                            ),
                          ),
                          if (_errorMessage.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                _errorMessage,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colorScheme.error,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                        ],
                      )
                    else if (_hasError)
                      Column(
                        children: [
                          Icon(
                            Icons.shopping_cart,
                            size: 48,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Widdle Reader is a premium app',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onBackground,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _errorMessage,
                            style: TextStyle(
                              fontSize: 14,
                              color: colorScheme.onBackground.withOpacity(0.7),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            icon: const Icon(Icons.shopping_bag_outlined),
                            label: const Text('Purchase from Google Play'),
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                            onPressed: _launchGooglePlay,
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            child: const Text('Check Again'),
                            onPressed: _checkLicense,
                          ),
                        ],
                      ),
                      
                    const Spacer(),
                    
                    // Price tag at the bottom
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'One-time purchase: \$1.99',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
} 