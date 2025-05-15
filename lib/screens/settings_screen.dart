import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/app_logo.dart';
import '../utils/responsive_utils.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  Color _currentColor = Colors.blue;
  bool _showColorPicker = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  
  // Track if we should show staggered animations
  bool _showStaggeredAnimations = true;

  @override
  void initState() {
    super.initState();
    
    // Initialize animation controller with slightly longer duration for smoother feel
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    
    // Create a curved animation for more natural feel
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
    
    // Add a slide animation for more dynamic transitions
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    
    _animationController.forward();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      setState(() {
        _currentColor = themeProvider.seedColor;
      });
      
      // Delay setting this to false to allow for initial animations
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() {
            _showStaggeredAnimations = false;
          });
        }
      });
    });
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      // Use an animated theme transition for smooth color changes
      body: TweenAnimationBuilder<Color?>(
        tween: ColorTween(
          begin: colorScheme.surface,
          end: colorScheme.surface,
        ),
        duration: const Duration(milliseconds: 300),
        builder: (context, color, child) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: AppTheme.gradientBackground(context),
            child: child,
          );
        },
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              decelerationRate: ScrollDecelerationRate.fast,
            ),
            slivers: [
              // App Bar with smoother back button animation
              SliverAppBar(
                floating: true,
                pinned: true,
                title: const Text('Settings'),
                leading: Hero(
                  tag: 'back_button',
                  child: Material(
                    color: Colors.transparent,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () {
                        // Add a smooth exit animation
                        _animationController.reverse().then((_) {
                          Navigator.of(context).pop();
                        });
                      },
                    ),
                  ),
                ),
                elevation: 0,
                scrolledUnderElevation: 3,
              ),
              
              // Content with enhanced animations
              SliverFadeTransition(
                opacity: _fadeAnimation,
                sliver: SliverToBoxAdapter(
                  child: AnimatedBuilder(
                    animation: _slideAnimation,
                    builder: (context, child) {
                      return SlideTransition(
                        position: _slideAnimation,
                        child: context.isLandscape
                            ? _buildLandscapeLayout(themeProvider, colorScheme, textTheme)
                            : _buildPortraitLayout(themeProvider, colorScheme, textTheme),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Portrait layout - scrollable single column with staggered animation delays
  Widget _buildPortraitLayout(
    ThemeProvider themeProvider,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Appearance section
          _buildSectionWithDelay(
            'Appearance',
            Icons.palette_outlined,
            textTheme, 
            colorScheme, 
            delay: 50,
          ),
          const SizedBox(height: 12),
          _buildAnimatedCard(
            _buildThemeModeCard(themeProvider, colorScheme, textTheme),
            delay: 100,
          ),
          _buildAnimatedCard(
            _buildSeedColorCard(themeProvider, colorScheme, textTheme),
            delay: 150,
          ),
          if (!_showColorPicker) 
            _buildAnimatedCard(
              _buildMaterialColorPalette(themeProvider, colorScheme, textTheme),
              delay: 200,
            ),

          // About section with delay
          _buildSectionWithDelay(
            'About',
            Icons.info_outline_rounded,
            textTheme,
            colorScheme,
            delay: 250,
          ),
          const SizedBox(height: 12),
          _buildAnimatedCard(
            _buildAboutCard(colorScheme, textTheme),
            delay: 300,
          ),
        ],
      ),
    );
  }

  // Landscape layout with staggered animations for columns
  Widget _buildLandscapeLayout(
    ThemeProvider themeProvider,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left column with staggered animation
          Expanded(
            child: _buildAnimatedContainer(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionWithDelay(
                    'Appearance',
                    Icons.palette_outlined,
                    textTheme,
                    colorScheme,
                    delay: 50,
                  ),
                  const SizedBox(height: 12),
                  _buildAnimatedCard(
                    _buildThemeModeCard(themeProvider, colorScheme, textTheme),
                    delay: 100,
                  ),
                  _buildAnimatedCard(
                    _buildSeedColorCard(themeProvider, colorScheme, textTheme),
                    delay: 150,
                  ),
                  if (!_showColorPicker) 
                    _buildAnimatedCard(
                      _buildMaterialColorPalette(themeProvider, colorScheme, textTheme),
                      delay: 200,
                    ),
                ],
              ),
              delay: 0,
            ),
          ),

          // Middle divider
          const SizedBox(width: 32),

          // Right column with staggered animation
          Expanded(
            child: _buildAnimatedContainer(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionWithDelay(
                    'About',
                    Icons.info_outline_rounded,
                    textTheme,
                    colorScheme,
                    delay: 75,
                  ),
                  const SizedBox(height: 12),
                  _buildAnimatedCard(
                    _buildAboutCard(colorScheme, textTheme),
                    delay: 125,
                  ),
                ],
              ),
              delay: 100,
            ),
          ),
        ],
      ),
    );
  }

  // Wrapper for animated cards with staggered delay
  Widget _buildAnimatedCard(Widget child, {required int delay}) {
    if (!_showStaggeredAnimations) return child;
    
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        // Calculate a delayed progress based on the original animation
        final delayedProgress = _calculateDelayedProgress(
          _animationController.value,
          delay / 1000, // Convert to seconds
        );
        
        return Opacity(
          opacity: delayedProgress,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - delayedProgress)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
  
  // Helper for smoother delayed animations
  double _calculateDelayedProgress(double progress, double delay) {
    // Compress the animation into a shorter timeframe after the delay
    final adjustedProgress = (progress - delay) / (1.0 - delay);
    // Ensure it stays within 0-1 bounds
    return adjustedProgress.clamp(0.0, 1.0);
  }
  
  // Container with staggered animation
  Widget _buildAnimatedContainer(Widget child, {required int delay}) {
    if (!_showStaggeredAnimations) return child;
    
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final delayedProgress = _calculateDelayedProgress(
          _animationController.value,
          delay / 1000,
        );
        
        return Opacity(
          opacity: delayedProgress,
          child: Transform.translate(
            offset: Offset(10 * (1 - delayedProgress), 0),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  // Section header with staggered animation
  Widget _buildSectionWithDelay(
    String title,
    IconData icon,
    TextTheme textTheme,
    ColorScheme colorScheme,
    {required int delay}
  ) {
    final sectionHeader = _buildSectionHeader(
      title, 
      icon, 
      textTheme, 
      colorScheme,
    );
    
    if (!_showStaggeredAnimations) return sectionHeader;
    
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final delayedProgress = _calculateDelayedProgress(
          _animationController.value,
          delay / 1000,
        );
        
        return Opacity(
          opacity: delayedProgress,
          child: Transform.translate(
            offset: Offset(20 * (1 - delayedProgress), 0),
            child: child,
          ),
        );
      },
      child: sectionHeader,
    );
  }

  // Theme mode selection card with enhanced animations
  Widget _buildThemeModeCard(
    ThemeProvider themeProvider,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final isLandscape = context.isLandscape;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(isLandscape ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Theme Mode',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: isLandscape ? 16 : 20),

            // Theme mode options row with enhanced animations
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildThemeModeOption(
                  context,
                  ThemeMode.light,
                  'Light',
                  Icons.wb_sunny_rounded,
                  themeProvider,
                ),
                _buildThemeModeOption(
                  context,
                  ThemeMode.dark,
                  'Dark',
                  Icons.nightlight_round,
                  themeProvider,
                ),
                _buildThemeModeOption(
                  context,
                  ThemeMode.system,
                  'System',
                  Icons.settings_suggest_rounded,
                  themeProvider,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Seed color selection card with smoother transitions
  Widget _buildSeedColorCard(
    ThemeProvider themeProvider,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final isLandscape = context.isLandscape;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(isLandscape ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Seed Color',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a color to personalize your app theme',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),

            // Color selection button with enhanced ripple effect
            InkWell(
              onTap: () {
                setState(() {
                  _showColorPicker = !_showColorPicker;
                });
              },
              borderRadius: BorderRadius.circular(16),
              splashColor: _currentColor.withOpacity(0.3),
              highlightColor: _currentColor.withOpacity(0.1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: _currentColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: _currentColor.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    'Tap to change color',
                    style: TextStyle(
                      color:
                          _currentColor.computeLuminance() > 0.5
                              ? Colors.black
                              : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),

            // Color picker expansion with smoother transitions
            AnimatedSize(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOutCubic,
              child: _showColorPicker
                  ? Container(
                      margin: const EdgeInsets.only(top: 20),
                      height: isLandscape ? 300 : 420,
                      child: Column(
                        children: [
                          Expanded(
                            child: ColorPicker(
                              pickerColor: _currentColor,
                              onColorChanged: (color) {
                                setState(() {
                                  _currentColor = color;
                                });
                              },
                              pickerAreaHeightPercent: 0.7,
                              enableAlpha: false,
                              displayThumbColor: true,
                              portraitOnly: false,
                              paletteType: PaletteType.hsvWithHue,
                              pickerAreaBorderRadius: BorderRadius.circular(
                                16,
                              ),
                              hexInputBar: true,
                              labelTypes: const [ColorLabelType.hex, ColorLabelType.rgb],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Apply button with enhanced visual feedback
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _showColorPicker = false;
                                  });
                                },
                                icon: const Icon(Icons.close),
                                label: const Text('Cancel'),
                              ),
                              FilledButton.icon(
                                onPressed: () {
                                  // Add a micro-animation for feedback
                                  final oldColor = themeProvider.seedColor;
                                  themeProvider.setSeedColor(_currentColor);
                                  setState(() {
                                    _showColorPicker = false;
                                  });
                                  _showThemeUpdatedSnackBar(context, oldColor);
                                },
                                icon: const Icon(Icons.check),
                                label: const Text('Apply Color'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: _currentColor,
                                  foregroundColor:
                                      _currentColor.computeLuminance() > 0.5
                                          ? Colors.black
                                          : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  // About card with enhanced animations
  Widget _buildAboutCard(ColorScheme colorScheme, TextTheme textTheme) {
    final isLandscape = context.isLandscape;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(isLandscape ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // App logo with pulse animation
            Hero(
              tag: 'app_logo',
              child: AppLogo(size: isLandscape ? 60 : 80),
            ),
            SizedBox(height: isLandscape ? 12 : 16),

            // App name
            Text(
              'Widdle Reader',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            // Version
            Text(
              'Version 1.0.0',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),

            // Tagline
            Text(
              'A beautiful, customizable audiobook player',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            
            // Add some vertical padding to match other cards
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // Material color palette for quick selection with enhanced animations
  Widget _buildMaterialColorPalette(
    ThemeProvider themeProvider, 
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final colors = [
      Colors.red,
      Colors.pink,
      Colors.purple,
      Colors.deepPurple,
      Colors.indigo,
      Colors.blue,
      Colors.lightBlue,
      Colors.cyan,
      Colors.teal,
      Colors.green,
      Colors.lightGreen,
      Colors.lime,
      Colors.yellow,
      Colors.amber,
      Colors.orange,
      Colors.deepOrange,
      Colors.brown,
      Colors.grey,
      Colors.blueGrey,
    ];

    final isLandscape = context.isLandscape;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(isLandscape ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Colors',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose from our pre-selected colors',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: colors.asMap().entries.map((entry) {
                final index = entry.key;
                final color = entry.value;
                final isSelected = themeProvider.seedColor.value == color.value;
                
                // Add staggered animation for color palette items
                return _buildAnimatedColorSwatch(
                  color: color,
                  isSelected: isSelected,
                  onTap: () {
                    // Add tactile feedback
                    HapticFeedback.selectionClick();
                    themeProvider.setSeedColor(color);
                    setState(() {
                      _currentColor = color;
                    });
                    _showThemeUpdatedSnackBar(context, themeProvider.seedColor);
                  },
                  delay: index * 20, // Stagger the animations
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
  
  // Animated color swatch with staggered animation
  Widget _buildAnimatedColorSwatch({
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
    required int delay,
  }) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        // Only apply staggered animation during initial load
        if (!_showStaggeredAnimations) return child!;
        
        final delayedProgress = _calculateDelayedProgress(
          _animationController.value,
          delay / 1000,
        );
        
        return Opacity(
          opacity: delayedProgress,
          child: Transform.scale(
            scale: 0.5 + (0.5 * delayedProgress),
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(isSelected ? 12 : 21),
            border: isSelected
                ? Border.all(
                    color: Colors.white,
                    width: 2,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: isSelected ? 6 : 3,
                spreadRadius: isSelected ? 1 : 0,
                offset: isSelected
                    ? const Offset(0, 2)
                    : const Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Section header
  Widget _buildSectionHeader(
    String title,
    IconData icon,
    TextTheme textTheme,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8, top: 16),
      child: Row(
        children: [
          Icon(icon, color: colorScheme.primary, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // Theme mode option button with enhanced animations
  Widget _buildThemeModeOption(
    BuildContext context,
    ThemeMode mode,
    String label,
    IconData icon,
    ThemeProvider themeProvider,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = themeProvider.themeMode == mode;

    return GestureDetector(
      onTap: () {
        // Add tactile feedback
        HapticFeedback.selectionClick();
        themeProvider.setThemeMode(mode);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected 
              ? colorScheme.primaryContainer 
              : colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: colorScheme.shadow.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Add scale animation for the icon when selected
            TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: isSelected ? 1.0 : 0.8,
                end: isSelected ? 1.1 : 1.0,
              ),
              duration: const Duration(milliseconds: 300),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Icon(
                    icon,
                    color: isSelected 
                        ? colorScheme.onPrimaryContainer 
                        : colorScheme.onSurfaceVariant,
                    size: 24,
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected 
                    ? colorScheme.onPrimaryContainer 
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Show a snackbar when theme is updated with color transition effect
  void _showThemeUpdatedSnackBar(BuildContext context, Color previousColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            // Add a small animation showing the color transition
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: _currentColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  Icons.check,
                  color: _currentColor.computeLuminance() > 0.5 
                      ? Colors.black 
                      : Colors.white,
                  size: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Text('Theme updated'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {},
          textColor: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// A fade transition sliver that works with CustomScrollView
class SliverFadeTransition extends StatelessWidget {
  final Animation<double> opacity;
  final Widget sliver;

  const SliverFadeTransition({
    super.key,
    required this.opacity,
    required this.sliver,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAnimatedOpacity(
      opacity: opacity.value,
      sliver: sliver,
      duration: Duration.zero, // No animation duration needed as we use the provided animation
    );
  }
}

/// Animated Builder for slivers to apply transformations
class SliverAnimatedBuilder extends StatelessWidget {
  final Animation<dynamic> animation;
  final Widget Function(BuildContext, Widget?) builder;
  
  const SliverAnimatedBuilder({
    super.key,
    required this.animation,
    required this.builder,
  });
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => builder(context, child),
    );
  }
}
