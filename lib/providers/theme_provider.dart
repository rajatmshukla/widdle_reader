import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:palette_generator/palette_generator.dart';

/// A ChangeNotifier that manages the app's theme mode and seed color
class ThemeProvider extends ChangeNotifier {
  static const String _themePreferenceKey = 'theme_mode';
  static const String _seedColorKey = 'seed_color';
  static const String _dynamicThemeKey = 'dynamic_theme_enabled';
  static const String _amoledBlackKey = 'amoled_black_enabled';

  /// Current theme mode (light, dark, or system)
  ThemeMode _themeMode = ThemeMode.system;

  /// Current seed color for generating the theme
  Color _seedColor = Colors.blue; // Default blue seed color

  /// Whether dynamic theme based on cover art is enabled
  bool _isDynamicThemeEnabled = false;

  /// Whether pure black AMOLED theme is enabled in dark mode
  bool _useAmoledBlack = false;

  /// Get the current theme mode
  ThemeMode get themeMode => _themeMode;

  /// Get the current seed color
  Color get seedColor => _seedColor;

  /// Get whether dynamic theme is enabled
  bool get isDynamicThemeEnabled => _isDynamicThemeEnabled;

  /// Get whether amoled black is enabled
  bool get useAmoledBlack => _useAmoledBlack;

  /// Initialize the theme provider
  ThemeProvider() {
    _loadPreferences();
  }

  /// Load saved theme preferences from shared preferences
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load theme mode
      final savedMode = prefs.getString(_themePreferenceKey);
      if (savedMode != null) {
        _themeMode = _parseThemeMode(savedMode);
      }

      // Load seed color
      final savedColorValue = prefs.getInt(_seedColorKey);
      if (savedColorValue != null) {
        _seedColor = Color(savedColorValue);
      }

      // Load dynamic theme setting
      _isDynamicThemeEnabled = prefs.getBool(_dynamicThemeKey) ?? false;

      // Load library view mode (default to Grid View)
      _isGridView = prefs.getBool('library_is_grid_view') ?? true;

      // Load amoled black setting
      _useAmoledBlack = prefs.getBool(_amoledBlackKey) ?? false;

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading theme preferences: $e');
    }
  }

  /// Save theme mode preference to shared preferences
  Future<void> _saveThemeMode(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themePreferenceKey, mode.toString());
    } catch (e) {
      debugPrint('Error saving theme mode: $e');
    }
  }

  /// Save seed color preference to shared preferences
  Future<void> _saveSeedColor(Color color) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_seedColorKey, color.value);
    } catch (e) {
      debugPrint('Error saving seed color: $e');
    }
  }

  /// Convert string to ThemeMode enum
  ThemeMode _parseThemeMode(String value) {
    switch (value) {
      case 'ThemeMode.light':
        return ThemeMode.light;
      case 'ThemeMode.dark':
        return ThemeMode.dark;
      case 'ThemeMode.system':
        return ThemeMode.system;
      default:
        return ThemeMode.system;
    }
  }

  /// Update the theme mode
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode != mode) {
      _themeMode = mode;
      await _saveThemeMode(mode);
      notifyListeners();
    }
  }

  /// Toggle between light and dark mode
  Future<void> toggleTheme() async {
    final newMode =
        _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    await setThemeMode(newMode);
  }

  /// Update the seed color
  Future<void> setSeedColor(Color color) async {
    if (_seedColor != color) {
      _seedColor = color;
      await _saveSeedColor(color);
      notifyListeners();
    }
  }

  /// Check if current theme is dark mode
  bool get isDarkMode {
    if (_themeMode == ThemeMode.system) {
      // When using system, depend on platform brightness
      return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  /// Enable or disable dynamic theme based on cover art
  Future<void> setDynamicThemeEnabled(bool enabled) async {
    if (_isDynamicThemeEnabled != enabled) {
      _isDynamicThemeEnabled = enabled;
      
      // Save to preferences
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_dynamicThemeKey, enabled);
      } catch (e) {
        debugPrint('Error saving dynamic theme preference: $e');
      }
      
      // Revert or update UI state immediately
      notifyListeners();
    }
  }

  /// Enable or disable pure black AMOLED theme
  Future<void> setAmoledBlack(bool enabled) async {
    if (_useAmoledBlack != enabled) {
      _useAmoledBlack = enabled;
      
      // Save to preferences
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_amoledBlackKey, enabled);
      } catch (e) {
        debugPrint('Error saving amoled black preference: $e');
      }
      
      notifyListeners();
    }
  }

  /// Update theme color from an image (e.g., audiobook cover art)
  /// Uses a smarter selection to pick the most abundant and visually appealing color
  Future<void> updateThemeFromImage(ImageProvider imageProvider) async {
    if (!_isDynamicThemeEnabled) return;
    
    try {
      final PaletteGenerator paletteGenerator = 
          await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: 32, // Increased for better color detection
      );
      
      // Smart color selection priority:
      // 1. Muted color (often the most representative and pleasant)
      // 2. Light Muted (good for covers with muted tones)
      // 3. Dominant color (most abundant)
      // 4. Vibrant color (most saturated, but sometimes too bright)
      // 5. Dark Vibrant (good for darker covers)
      // 6. Light Vibrant (last resort)
      
      Color? newColor;
      
      // First, try to get a color that's both abundant and visually pleasant
      // Muted colors are often the best representation of the artwork's mood
      if (paletteGenerator.mutedColor != null) {
        newColor = paletteGenerator.mutedColor!.color;
      } else if (paletteGenerator.lightMutedColor != null) {
        newColor = paletteGenerator.lightMutedColor!.color;
      } else if (paletteGenerator.dominantColor != null) {
        // Dominant is the most abundant color
        newColor = paletteGenerator.dominantColor!.color;
      } else if (paletteGenerator.vibrantColor != null) {
        newColor = paletteGenerator.vibrantColor!.color;
      } else if (paletteGenerator.darkVibrantColor != null) {
        newColor = paletteGenerator.darkVibrantColor!.color;
      } else if (paletteGenerator.lightVibrantColor != null) {
        newColor = paletteGenerator.lightVibrantColor!.color;
      }
      
      // If we still don't have a color, pick from the palette colors directly
      if (newColor == null && paletteGenerator.colors.isNotEmpty) {
        // Pick the color with the highest population (most abundant)
        PaletteColor? bestColor;
        int maxPopulation = 0;
        for (final color in paletteGenerator.paletteColors) {
          if (color.population > maxPopulation) {
            maxPopulation = color.population;
            bestColor = color;
          }
        }
        newColor = bestColor?.color;
      }
      
      if (newColor != null) {
        // Ensure the color isn't too dark or too light for theming
        final hsl = HSLColor.fromColor(newColor);
        if (hsl.lightness < 0.15) {
          // Too dark - lighten it a bit
          newColor = hsl.withLightness(0.25).toColor();
        } else if (hsl.lightness > 0.85) {
          // Too light - darken it a bit
          newColor = hsl.withLightness(0.75).toColor();
        }
        
        // Boost saturation slightly if it's too muted
        if (hsl.saturation < 0.2) {
          final adjustedHsl = HSLColor.fromColor(newColor);
          newColor = adjustedHsl.withSaturation(0.35).toColor();
        }
        
        _seedColor = newColor;
        notifyListeners();
        debugPrint('Dynamic theme updated to: ${newColor.toString()} (HSL: L=${hsl.lightness.toStringAsFixed(2)}, S=${hsl.saturation.toStringAsFixed(2)})');
      }
    } catch (e) {
      debugPrint('Error extracting color from image: $e');
      // Silently fail - keep current color
    }
  }

  /// Reset to default color (used when no audiobook is playing)
  void resetToDefaultColor() {
    if (!_isDynamicThemeEnabled) return;
    
    _seedColor = Colors.blue;
    notifyListeners();
  }

  // Library View Mode State (default to Grid View)
  bool _isGridView = true;
  bool get isGridView => _isGridView;

  /// Set the library view mode
  Future<void> setGridView(bool isGrid) async {
    if (_isGridView != isGrid) {
      _isGridView = isGrid;
      notifyListeners();
      
      // Save to storage
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('library_is_grid_view', isGrid);
      } catch (e) {
        debugPrint('Error saving view mode preference: $e');
      }
    }
  }

  /// Toggle between list and grid view
  Future<void> toggleViewMode() async {
    await setGridView(!_isGridView);
  }
}
