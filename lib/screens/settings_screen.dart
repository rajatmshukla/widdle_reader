import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart' as provider;
import '../providers/theme_provider.dart';
import '../widgets/app_logo.dart';
import '../utils/responsive_utils.dart';
import '../theme.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../services/simple_audio_service.dart';

import 'package:share_plus/share_plus.dart';
import '../services/storage_service.dart';
import '../services/native_scanner.dart';
import '../services/notification_service.dart';
import '../services/pulse_sync_service.dart';
import '../providers/audiobook_provider.dart';
import '../providers/tag_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> with SingleTickerProviderStateMixin {
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
      final themeProvider = provider.Provider.of<ThemeProvider>(context, listen: false);
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
    final themeProvider = provider.Provider.of<ThemeProvider>(context);
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
                title: Row(
                  children: [
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: AppLogo(size: 28, showTitle: false),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Settings',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
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
            _buildViewModeCard(themeProvider, colorScheme, textTheme),
            delay: 115,
          ),
          _buildAnimatedCard(
            _buildDynamicThemeCard(themeProvider, colorScheme, textTheme),
            delay: 125,
          ),
          if (!themeProvider.isDynamicThemeEnabled) ...[
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

          // Data Management section moved up
          _buildSectionWithDelay(
            'Data Management',
            Icons.storage_rounded,
            textTheme,
            colorScheme,
            delay: 250,
          ),
          const SizedBox(height: 12),
          _buildAnimatedCard(
            _buildDataManagementCard(colorScheme, textTheme),
            delay: 300,
          ),

          // Sync Section (New)
          _buildSectionWithDelay(
            'Sync',
            Icons.sync_rounded,
             textTheme,
             colorScheme,
             delay: 325,
          ),
           const SizedBox(height: 12),
           _buildAnimatedCard(
             _buildSyncCard(colorScheme, textTheme),
             delay: 340,
           ),

          // Notifications section
          _buildSectionWithDelay(
            'Notifications',
            Icons.notifications_rounded,
            textTheme,
            colorScheme,
            delay: 350,
          ),
          const SizedBox(height: 12),
          _buildAnimatedCard(
            _buildNotificationCard(colorScheme, textTheme),
            delay: 400,
          ),

          // About section moved to the end
          _buildSectionWithDelay(
          'About',
          Icons.info_outline_rounded,
          textTheme,
          colorScheme,
            delay: 700,
        ),
          const SizedBox(height: 12),
          _buildAnimatedCard(
        _buildAboutCard(colorScheme, textTheme),
            delay: 800,
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
                    _buildViewModeCard(themeProvider, colorScheme, textTheme),
                    delay: 115,
                  ),
                  _buildAnimatedCard(
                    _buildDynamicThemeCard(themeProvider, colorScheme, textTheme),
                    delay: 125,
                  ),
                  if (!themeProvider.isDynamicThemeEnabled) ...[
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
                  // Data Management moved up
                  _buildSectionWithDelay(
                    'Data Management',
                    Icons.storage_rounded,
                textTheme,
                colorScheme,
                    delay: 75,
                  ),
                  const SizedBox(height: 12),
                  _buildAnimatedCard(
                    _buildDataManagementCard(colorScheme, textTheme),
                    delay: 125,
                  ),

                  // Sync Section (New)
                  _buildSectionWithDelay(
                    'Sync',
                    Icons.sync_rounded,
                     textTheme,
                     colorScheme,
                     delay: 135,
                  ),
                   const SizedBox(height: 12),
                   _buildAnimatedCard(
                     _buildSyncCard(colorScheme, textTheme),
                     delay: 145,
                   ),

                  // Notifications section
                  _buildSectionWithDelay(
                    'Notifications',
                    Icons.notifications_rounded,
                    textTheme,
                    colorScheme,
                    delay: 150,
                  ),
                  const SizedBox(height: 12),
                  _buildAnimatedCard(
                    _buildNotificationCard(colorScheme, textTheme),
                    delay: 175,
                  ),

                  // About moved to the end
                  _buildSectionWithDelay(
                    'About',
                    Icons.info_outline_rounded,
                textTheme,
                colorScheme,
                    delay: 200,
                  ),
                  const SizedBox(height: 12),
                  _buildAnimatedCard(
                    _buildAboutCard(colorScheme, textTheme),
                    delay: 250,
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

  // View Mode Card (Grid vs List)
  Widget _buildViewModeCard(
    ThemeProvider themeProvider,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final isGridView = themeProvider.isGridView;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isGridView ? Icons.grid_view_rounded : Icons.view_list_rounded,
                  color: colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Library Layout',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isGridView ? 'Grid View' : 'List View',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isGridView,
                  onChanged: (value) => themeProvider.setGridView(value),
                  thumbIcon: WidgetStateProperty.resolveWith<Icon?>(
                    (Set<WidgetState> states) {
                      if (states.contains(WidgetState.selected)) {
                        return const Icon(Icons.grid_view_rounded);
                      }
                      return const Icon(Icons.view_list_rounded);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Dynamic Theme card
  Widget _buildDynamicThemeCard(
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dynamic Theme',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Adapt theme to audiobook cover art',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: themeProvider.isDynamicThemeEnabled,
                  onChanged: (value) {
                    // Start the process but don't await to keep UI snappy
                    themeProvider.setDynamicThemeEnabled(value);
                    
                    // If enabling and currently playing, extract color from audiobook
                    if (value && mounted) {
                      final audioService = SimpleAudioService();
                      final currentBook = audioService.currentAudiobook;
                      
                      if (currentBook?.coverArt != null) {
                        // Use unawaited for background extraction
                        themeProvider.updateThemeFromImage(
                          MemoryImage(currentBook!.coverArt!),
                        );
                      }
                    } else if (!value) {
                      // Reset to saved manual color when disabling
                      setState(() {});
                    }
                  },
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
              'Version 2.0.0',
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
      // Material colors
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
      
      // Pastel colors
      const Color(0xFFFFD1DC), // Pastel pink
      const Color(0xFFB5EAD7), // Pastel mint
      const Color(0xFFC7CEEA), // Pastel blue
      const Color(0xFFFFECD1), // Pastel peach
      const Color(0xFFFFC8DD), // Pastel rose
      
      // Vibrant modern colors
      const Color(0xFF6200EA), // Deep purple
      const Color(0xFF00B8D4), // Bright cyan
      const Color(0xFF00C853), // Bright green
      const Color(0xFFFFD600), // Bright yellow
      const Color(0xFFFF6E40), // Bright orange
      
      // Trendy colors
      const Color(0xFF80DEEA), // Seafoam
      const Color(0xFFD1C4E9), // Lavender
      const Color(0xFFF48FB1), // Coral
      const Color(0xFFBCAAA4), // Taupe
      const Color(0xFF536DFE), // Electric blue
      const Color(0xFF2E7D32), // Forest green
      const Color(0xFF5D4037), // Cocoa
      const Color(0xFF212121), // Night
      
      // Special colors
      const Color(0xFF01579B), // Navy blue
      const Color(0xFF004D40), // Dark teal
      const Color(0xFF263238), // Dark slate
      const Color(0xFF880E4F), // Wine
      const Color(0xFF311B92), // Deep indigo
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
              'Choose from our expanded color palette',
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
                  delay: index * 15, // Reduce the delay with more colors
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

  // Data Management card
  Widget _buildDataManagementCard(
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final isLandscape = ResponsiveUtils.isLandscape(context);

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
            // Data backup option (enhanced)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.backup_rounded, color: colorScheme.primary),
              title: Text('Backup User Data', style: textTheme.bodyMedium),
              subtitle: Text(
                'Export all your data including statistics & progress',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              onTap: () => _backupUserData(context),
            ),
            
            // Data restore option
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.restore_rounded, color: colorScheme.primary),
              title: Text('Restore from Backup', style: textTheme.bodyMedium),
              subtitle: Text(
                'Import your data from a backup file',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              onTap: () => _restoreUserData(context),
            ),
            
            // Check data health option
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.verified_rounded, color: colorScheme.primary),
              title: Text('Check Data Health', style: textTheme.bodyMedium),
              subtitle: Text(
                'Verify and repair data integrity if needed',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              onTap: () => _checkDataHealth(context),
            ),
            
            // Scan library for tags option
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.local_offer_outlined, color: colorScheme.secondary),
              title: Text('Scan Library for Tags', style: textTheme.bodyMedium),
              subtitle: Text(
                'Create tags from existing books\' folder structure',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              onTap: () => _scanLibraryForTags(context),
            ),
            

          ],
        ),
      ),
    );
  }

  // Notification Settings card
  Widget _buildNotificationCard(
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final isLandscape = ResponsiveUtils.isLandscape(context);
    final storageService = StorageService();

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
            // Notifications enabled toggle
            FutureBuilder<bool>(
              future: storageService.getNotificationsEnabled(),
              builder: (context, snapshot) {
                final notificationsEnabled = snapshot.data ?? true;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    notificationsEnabled 
                      ? Icons.notifications_active_rounded 
                      : Icons.notifications_off_rounded,
                    color: notificationsEnabled 
                      ? colorScheme.primary 
                      : colorScheme.onSurfaceVariant,
                  ),
                  title: Text('Enable Notifications', style: textTheme.bodyMedium),
                  subtitle: Text(
                    'Daily reading reminders and achievements',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  trailing: Switch(
                    value: notificationsEnabled,
                    onChanged: (value) async {
                      await storageService.setNotificationsEnabled(value);
                      setState(() {}); // Refresh to show updated state
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              value 
                                ? 'Notifications enabled'
                                : 'Notifications disabled',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
                );
              },
            ),
            
          ],
        ),
      ),
    );
  }

  /// Build the data backup and restore section
  Future<void> _backupUserData(BuildContext context) async {
    final storageService = StorageService();
    
    try {
      // 1. Ask user to pick location first (before showing progress)
      final now = DateTime.now().toIso8601String().replaceAll(':', '_');
      final suggestedName = 'widdle_reader_backup_$now.json';
      final String? targetUri = await NativeScanner.createFile(suggestedName, 'application/json');
      
      // User cancelled
      if (targetUri == null) return;

      // 2. Now show progress dialog
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            title: Text('Creating Backup'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Exporting your data...'),
              ],
            ),
          ),
        );
      }
      
      // 3. Export
      final backupPath = await storageService.exportUserDataToUri(targetUri);
      
      // Close the progress dialog
      if (context.mounted) Navigator.of(context).pop();
      
      if (backupPath != null) {
        // Show success
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Backup Created'),
              content: Text('Backup saved successfully to selected folder.\n\nPath: $backupPath'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      } else {
        // Show error
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to create backup'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      // Close progress dialog if open
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      
      // Show error
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
  
  // Restore user data
  Future<void> _restoreUserData(BuildContext context) async {
    try {
      // Show warning dialog first
      final confirmRestore = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore Data'),
          content: const Text(
            'Restoring from a backup will overwrite your current data. '
            'We recommend creating a backup of your current data first.\n\n'
            'Do you want to continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('CONTINUE'),
            ),
          ],
        ),
      );
      
      if (confirmRestore != true) return;
      
      // Pick a backup file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      
      if (result == null || result.files.isEmpty) return;
      
      final filePath = result.files.first.path;
      if (filePath == null) return;
      
      // Show progress dialog
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            title: Text('Restoring Data'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Importing your data...'),
          ],
        ),
      ),
    );
  }

      final storageService = StorageService();
      final success = await storageService.importUserData(File(filePath));
      
      // Close the progress dialog
      if (context.mounted) Navigator.of(context).pop();
      
      // Show result
      if (context.mounted) {
        if (success) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Restore Successful'),
              content: const Text(
                'Your data has been restored successfully. '
                'You may need to restart the app to see all changes.',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
            ),
          ],
        ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to restore data. The backup file may be invalid or corrupted.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      // Close progress dialog if open
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      
      // Show error
      if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
            content: Text('Error: $e'),
        behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
  
  // Check data health
  Future<void> _checkDataHealth(BuildContext context) async {
    final storageService = StorageService();
    
    // Show progress dialog
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          title: Text('Checking Data'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Verifying data integrity...'),
            ],
          ),
        ),
      );
    }
    
    try {
      // Check data health
      final healthCheck = await storageService.checkDataHealth();
      
      // Create a backup as a safety measure
      await storageService.createDataBackup();
      
      // Close the progress dialog
      if (context.mounted) Navigator.of(context).pop();
      
      // Show results
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Data Health Check'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Data Version: ${healthCheck['dataVersion'] ?? 'Unknown'}/${healthCheck['currentVersion'] ?? 'Unknown'}'),
                  const SizedBox(height: 8),
                  Text('Last Cache Sync: ${healthCheck['lastCacheSync'] ?? 'Never'}'),
                  const SizedBox(height: 16),
                  const Text('Data Counts:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('• Audiobooks: ${healthCheck['counts']?['folders'] ?? 0}'),
                  Text('• Progress Records: ${healthCheck['counts']?['progress'] ?? 0}'),
                  Text('• Position Records: ${healthCheck['counts']?['positions'] ?? 0}'),
                  Text('• Bookmarks: ${healthCheck['counts']?['bookmarks'] ?? 0}'),
                  Text('• Completed Books: ${healthCheck['counts']?['completedBooks'] ?? 0}'),
                  Text('• Custom Titles: ${healthCheck['counts']?['customTitles'] ?? 0}'),
                  Text('• User Tags: ${healthCheck['counts']?['userTags'] ?? 0}'),
                  Text('• Tag Assignments: ${healthCheck['counts']?['audiobookTagAssignments'] ?? 0}'),
                  Text('• Reading Sessions: ${healthCheck['counts']?['readingSessions'] ?? 0}'),
                  Text('• Daily Stats: ${healthCheck['counts']?['dailyStats'] ?? 0}'),
                  Text('• Achievements: ${healthCheck['counts']?['achievements'] ?? 0}'),
                  Text('• Active Challenges: ${healthCheck['counts']?['activeChallenges'] ?? 0}'),
                  Text('• Equalizer Settings: ${healthCheck['counts']?['equalizerSettings'] ?? 0}'),
                  Text('• Duration Preferences: ${healthCheck['counts']?['durationModes'] ?? 0}'),
                  Text('• Completion Flags: ${healthCheck['counts']?['completionFlags'] ?? 0}'),
                  Text('• Manual Covers: ${healthCheck['counts']?['manualCovers'] ?? 0}'),
                  if (healthCheck['error'] != null) ...[
                    const SizedBox(height: 16),
                    Text('⚠️ Error: ${healthCheck['error']}', style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 16),
                  const Text('A backup of your data was created as a safety measure.'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('CLOSE'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _attemptDataRecovery(context);
                },
                child: const Text('ATTEMPT RECOVERY'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // Close progress dialog if still open
      if (context.mounted) {
         // This is a bit risky if we don't know for sure the dialog is open, 
         // but since barrierDismissible is false, it's likely the only one.
         try { Navigator.of(context).pop(); } catch (_) {}
      }
      
      // Show error
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
  
  // Attempt data recovery
  Future<void> _attemptDataRecovery(BuildContext context) async {
    try {
      final storageService = StorageService();
      
      // Show progress dialog
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            title: Text('Recovering Data'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Attempting to recover data...'),
              ],
            ),
          ),
        );
      }
      
      // Attempt recovery
      final recovered = await storageService.restoreFromBackup();
      
      // Close the progress dialog
      if (context.mounted) Navigator.of(context).pop();
      
      // Show result
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(recovered 
              ? 'Data recovery successful' 
              : 'No recovery needed or no backup found'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      // Close progress dialog if open
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      
      // Show error
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // Scan existing library for auto-tags
  Future<void> _scanLibraryForTags(BuildContext context) async {
    try {
      final audiobookProvider = provider.Provider.of<AudiobookProvider>(context, listen: false);
      
      // Check if there are books to scan
      if (audiobookProvider.audiobooks.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No audiobooks in library to scan for tags'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // Show confirmation dialog
      final confirmScan = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Scan Library for Tags'),
          content: Text(
            'This will analyze ${audiobookProvider.audiobooks.length} audiobooks in your library and create tags based on their folder structure.\n\n'
            'This is useful for:\n'
            '• Recovering deleted tags\n'
            '• Creating series tags from folder names\n'
            '• Organizing books by genre or author\n\n'
            'Existing tags will not be duplicated.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('SCAN'),
            ),
          ],
        ),
      );

      if (confirmScan != true) return;

      // Show progress dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          title: Text('Scanning Library'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Analyzing folder structure and creating tags...'),
            ],
          ),
        ),
      );

      // Perform the scan
      await audiobookProvider.scanExistingLibraryForTags(ref);

      // Close progress dialog
      if (context.mounted) Navigator.of(context).pop();

      // Show success message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Library scan completed! Tags created from folder structure.'),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'VIEW TAGS',
              onPressed: () {
                // Navigate back and switch to tags view
                Navigator.of(context).pop(); // Close settings
                // Note: The navigation to tags view will be handled by the caller
              },
            ),
          ),
        );
      }

    } catch (e) {
      // Close progress dialog if open
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      
      // Show error
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error scanning library: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Widget _buildSyncCard(ColorScheme colorScheme, TextTheme textTheme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<bool>(
              future: StorageService().isPulseSyncEnabled(),
              initialData: true,
              builder: (context, snapshot) {
                final isEnabled = snapshot.data ?? true;
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Cross-Device Pulse Sync',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    'Sync progress and stats via a shared file (.widdle_pulse.json) in your library folder.',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: isEnabled,
                  onChanged: (value) async {
                    await StorageService().savePulseSyncEnabled(value);
                    setState(() {}); // Rebuild to update switch
                    
                    if (value) {
                       // Trigger an immediate sync if enabled
                       PulseSyncService().pulseIn();
                    }
                  },
                );
              },
            ),
             const SizedBox(height: 8),
            
            // Setup Guide
            ExpansionTile(
              title: Text(
                'How to set up syncing',
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
              iconColor: colorScheme.primary,
              collapsedIconColor: colorScheme.primary,
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 12),
              children: [
                _buildStepItem(
                  '1', 
                  'Install a file sync app', 
                  'Use a tool like Syncthing, Autosync, or Resilio Sync on both devices.',
                  colorScheme, textTheme
                ),
                const SizedBox(height: 12),
                _buildStepItem(
                  '2', 
                  'Sync your Audiobooks folder', 
                  'Configure the tool to sync your main Audiobooks library folder between your devices.',
                  colorScheme, textTheme
                ),
                const SizedBox(height: 12),
                _buildStepItem(
                  '3', 
                  'Enable Pulse Sync', 
                  'Turn on this toggle. Widdle Reader will automatically read and write to the shared .widdle_pulse.json file.',
                  colorScheme, textTheme
                ),
              ],
            ),

            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outlineVariant.withOpacity(0.5),
                ),
              ),
              child: Column(
                children: [
                   Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 20, color: colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Requires you to sync your library folder using a third-party tool (e.g., Syncthing, Autosync).',
                          style: textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Divider(height: 16, color: colorScheme.outlineVariant.withOpacity(0.3)),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.tips_and_updates_outlined, size: 20, color: colorScheme.tertiary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Tip: Pause playback before switching devices. This forces an immediate sync export, ensuring your other device picks up exactly where you left off.',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildStepItem(
    String number, 
    String title, 
    String description, 
    ColorScheme colorScheme, 
    TextTheme textTheme
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: TextStyle(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
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
