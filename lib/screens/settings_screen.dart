import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/app_logo.dart';
import '../utils/responsive_utils.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Color _currentColor = Colors.blue;
  bool _showColorPicker = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      setState(() {
        _currentColor = themeProvider.seedColor;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.arrow_back_rounded),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child:
            context.isLandscape
                ? _buildLandscapeLayout(themeProvider, colorScheme, textTheme)
                : _buildPortraitLayout(themeProvider, colorScheme, textTheme),
      ),
    );
  }

  // Portrait layout - scrollable single column
  Widget _buildPortraitLayout(
    ThemeProvider themeProvider,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Appearance section
        _buildSectionHeader(
          'Appearance',
          Icons.palette_outlined,
          textTheme,
          colorScheme,
        ),
        const SizedBox(height: 8),
        _buildThemeModeCard(themeProvider, colorScheme, textTheme),
        _buildSeedColorCard(themeProvider, colorScheme, textTheme),
        if (!_showColorPicker) _buildMaterialColorPalette(themeProvider),

        // About section
        _buildSectionHeader(
          'About',
          Icons.info_outline_rounded,
          textTheme,
          colorScheme,
        ),
        const SizedBox(height: 8),
        _buildAboutCard(colorScheme, textTheme),
      ],
    );
  }

  // Landscape layout - two column side by side
  Widget _buildLandscapeLayout(
    ThemeProvider themeProvider,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left column - Appearance
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSectionHeader(
                'Appearance',
                Icons.palette_outlined,
                textTheme,
                colorScheme,
              ),
              const SizedBox(height: 8),
              _buildThemeModeCard(themeProvider, colorScheme, textTheme),
              _buildSeedColorCard(themeProvider, colorScheme, textTheme),
              if (!_showColorPicker) _buildMaterialColorPalette(themeProvider),
            ],
          ),
        ),

        // Vertical divider
        Container(
          width: 1,
          height: double.infinity,
          color: colorScheme.outlineVariant,
          margin: const EdgeInsets.symmetric(vertical: 16),
        ),

        // Right column - About
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSectionHeader(
                'About',
                Icons.info_outline_rounded,
                textTheme,
                colorScheme,
              ),
              const SizedBox(height: 8),
              _buildAboutCard(colorScheme, textTheme),

              // Extra space for additional content
              const SizedBox(height: 24),

              // Support section in landscape only
              _buildSectionHeader(
                'Support',
                Icons.support_agent,
                textTheme,
                colorScheme,
              ),
              const SizedBox(height: 8),
              _buildSupportCard(colorScheme, textTheme),
            ],
          ),
        ),
      ],
    );
  }

  // Theme mode selection card
  Widget _buildThemeModeCard(
    ThemeProvider themeProvider,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final isLandscape = context.isLandscape;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(isLandscape ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Theme Mode',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: isLandscape ? 12 : 16),

            // Theme mode options row
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

  // Seed color selection card
  Widget _buildSeedColorCard(
    ThemeProvider themeProvider,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final isLandscape = context.isLandscape;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(isLandscape ? 12 : 16),
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
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 16),

            // Color selection button
            InkWell(
              onTap: () {
                setState(() {
                  _showColorPicker = !_showColorPicker;
                });
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _currentColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: _currentColor.withOpacity(0.4),
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
                    ),
                  ),
                ),
              ),
            ),

            // Color picker expansion
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              child:
                  _showColorPicker
                      ? Container(
                        margin: const EdgeInsets.only(top: 16),
                        height: isLandscape ? 300 : 500,
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
                                pickerAreaHeightPercent:
                                    isLandscape ? 0.5 : 0.7,
                                enableAlpha: false,
                                displayThumbColor: true,
                                portraitOnly: !isLandscape,
                                paletteType: PaletteType.hsv,
                                pickerAreaBorderRadius: BorderRadius.circular(
                                  16,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Apply button
                            ElevatedButton.icon(
                              onPressed: () {
                                themeProvider.setSeedColor(_currentColor);
                                setState(() {
                                  _showColorPicker = false;
                                });
                                _showThemeUpdatedSnackBar(context);
                              },
                              icon: const Icon(Icons.check),
                              label: const Text('Apply Color'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _currentColor,
                                foregroundColor:
                                    _currentColor.computeLuminance() > 0.5
                                        ? Colors.black
                                        : Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
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

  // About card
  Widget _buildAboutCard(ColorScheme colorScheme, TextTheme textTheme) {
    final isLandscape = context.isLandscape;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(isLandscape ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // App logo
            AppLogo(size: isLandscape ? 60 : 80),
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
            Text('Version 1.0.0', style: textTheme.bodyMedium),
            const SizedBox(height: 8),

            // Tagline
            Text(
              'A cute, customizable audiobook player',
              style: textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // Link to source code
            ListTile(
              leading: Icon(Icons.code_rounded, color: colorScheme.primary),
              title: const Text('Source Code'),
              subtitle: const Text('View on GitHub'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () {
                // Open GitHub or source code page
              },
            ),

            // Privacy policy
            ListTile(
              leading: Icon(
                Icons.privacy_tip_outlined,
                color: colorScheme.primary,
              ),
              title: const Text('Privacy Policy'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                // Show privacy policy
              },
            ),
          ],
        ),
      ),
    );
  }

  // Support card (only shown in landscape)
  Widget _buildSupportCard(ColorScheme colorScheme, TextTheme textTheme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.support_agent, color: colorScheme.primary, size: 48),
            const SizedBox(height: 16),

            Text(
              'Need Help?',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            Text(
              'We\'re here to help you with any questions or issues you might have.',
              style: textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // Support options
            ListTile(
              leading: Icon(Icons.email_outlined, color: colorScheme.primary),
              title: const Text('Email Support'),
              subtitle: const Text('support@widdlereader.com'),
              onTap: () {
                // Send email
              },
            ),

            ListTile(
              leading: Icon(Icons.help_outline, color: colorScheme.primary),
              title: const Text('FAQ'),
              subtitle: const Text('Frequently Asked Questions'),
              onTap: () {
                // Show FAQ
              },
            ),
          ],
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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

  // Theme mode option button
  Widget _buildThemeModeOption(
    BuildContext context,
    ThemeMode mode,
    String label,
    IconData icon,
    ThemeProvider themeProvider,
  ) {
    final isSelected = themeProvider.themeMode == mode;
    final colorScheme = Theme.of(context).colorScheme;
    final isLandscape = context.isLandscape;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: () => themeProvider.setThemeMode(mode),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: EdgeInsets.symmetric(
              vertical: isLandscape ? 8 : 12,
              horizontal: isLandscape ? 4 : 8,
            ),
            decoration: BoxDecoration(
              color:
                  isSelected
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
              border:
                  isSelected
                      ? Border.all(color: colorScheme.primary, width: 2)
                      : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color:
                      isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                  size: isLandscape ? 20 : 24,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: isLandscape ? 12 : 14,
                    color:
                        isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Material color palette
  Widget _buildMaterialColorPalette(ThemeProvider themeProvider) {
    final isLandscape = context.isLandscape;
    final colorScheme = Theme.of(context).colorScheme;

    // Predefined material design colors
    final List<Color> materialColors = [
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

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(isLandscape ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Colors',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: isLandscape ? 14 : 16,
              ),
            ),
            SizedBox(height: isLandscape ? 12 : 16),

            // Color grid
            Wrap(
              spacing: isLandscape ? 8 : 12,
              runSpacing: isLandscape ? 8 : 12,
              children:
                  materialColors.map((color) {
                    final isSelected = _currentColor.value == color.value;
                    return _buildColorSwatch(
                      color: color,
                      isSelected: isSelected,
                      isCompact: isLandscape,
                      onTap: () {
                        setState(() {
                          _currentColor = color;
                        });
                        themeProvider.setSeedColor(color);
                        _showThemeUpdatedSnackBar(context);
                      },
                    );
                  }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // Color swatch button
  Widget _buildColorSwatch({
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
    bool isCompact = false,
  }) {
    final size = isCompact ? 32.0 : 40.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child:
            isSelected
                ? Icon(
                  Icons.check,
                  color: Colors.white,
                  size: isCompact ? 16 : 20,
                )
                : null,
      ),
    );
  }

  // Show confirmation snackbar when theme is updated
  void _showThemeUpdatedSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Theme color updated'),
        backgroundColor: _currentColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        action: SnackBarAction(
          label: 'OK',
          textColor:
              _currentColor.computeLuminance() > 0.5
                  ? Colors.black
                  : Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }
}
