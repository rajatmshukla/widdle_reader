import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Color _currentColor = Colors.blue; // Default color
  bool _showColorPicker = false;

  @override
  void initState() {
    super.initState();
    // Initialize with the current seed color from the theme provider
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
              color: colorScheme.surfaceVariant.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.arrow_back_rounded),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Theme Section
          _buildSectionHeader(
            'Appearance',
            Icons.palette_outlined,
            textTheme,
            colorScheme,
          ),
          const SizedBox(height: 8),

          // Theme Mode Selection
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Theme Mode',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
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
          ),

          // Seed Color Selection
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                  InkWell(
                    onTap: () {
                      setState(() {
                        _showColorPicker = !_showColorPicker;
                      });
                    },
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

                  // Color Picker Expansion
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    child:
                        _showColorPicker
                            ? Container(
                              margin: const EdgeInsets.only(top: 16),
                              height: 500, // Fixed height for color picker
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
                                      portraitOnly: true,
                                      paletteType: PaletteType.hsv,
                                      pickerAreaBorderRadius:
                                          BorderRadius.circular(16),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      themeProvider.setSeedColor(_currentColor);
                                      setState(() {
                                        _showColorPicker = false;
                                      });
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: const Text(
                                            'Theme color updated',
                                          ),
                                          backgroundColor: _currentColor,
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                        ),
                                      );
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
          ),

          // Material Color Palette
          if (!_showColorPicker) _buildMaterialColorPalette(themeProvider),

          // About Section
          _buildSectionHeader(
            'About',
            Icons.info_outline_rounded,
            textTheme,
            colorScheme,
          ),
          const SizedBox(height: 8),

          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Widdle Reader',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Version 1.0.0', style: textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  Text(
                    'A cute, customizable audiobook player',
                    style: textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: Icon(
                      Icons.code_rounded,
                      color: colorScheme.primary,
                    ),
                    title: const Text('Source Code'),
                    subtitle: const Text('View on GitHub'),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () {
                      // Open GitHub or source code page
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

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

  Widget _buildThemeModeOption(
    BuildContext context,
    ThemeMode mode,
    String label,
    IconData icon,
    ThemeProvider themeProvider,
  ) {
    final isSelected = themeProvider.themeMode == mode;
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: () {
            themeProvider.setThemeMode(mode);
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color:
                  isSelected
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceVariant.withOpacity(0.3),
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
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
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

  Widget _buildMaterialColorPalette(ThemeProvider themeProvider) {
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Colors',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children:
                  materialColors.map((color) {
                    final isSelected = _currentColor.value == color.value;
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _currentColor = color;
                        });
                        themeProvider.setSeedColor(color);
                      },
                      borderRadius: BorderRadius.circular(50),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border:
                              isSelected
                                  ? Border.all(color: Colors.white, width: 2)
                                  : null,
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
                                ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 20,
                                )
                                : null,
                      ),
                    );
                  }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
