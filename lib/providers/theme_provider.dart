import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:palette_generator/palette_generator.dart';

/// A ChangeNotifier that manages the app's theme mode and seed color
class ThemeProvider extends ChangeNotifier {
  static const String _themePreferenceKey = 'theme_mode';
  static const String _seedColorKey = 'seed_color';
  static const String _dynamicThemeKey = 'dynamic_theme_enabled';

  /// Current theme mode (light, dark, or system)
  ThemeMode _themeMode = ThemeMode.system;

  /// Current seed color for generating the theme
  Color _seedColor = Colors.blue; // Default blue seed color

  /// Whether dynamic theme based on cover art is enabled
  bool _isDynamicThemeEnabled = false;

  /// Get the current theme mode
  ThemeMode get themeMode => _themeMode;

  /// Get the current seed color
  Color get seedColor => _seedColor;

  /// Get whether dynamic theme is enabled
  bool get isDynamicThemeEnabled => _isDynamicThemeEnabled;

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
      
      // If disabling, revert to saved seed color
      if (!enabled) {
        notifyListeners();
      }
    }
  }

  /// Update theme color from an image (e.g., audiobook cover art)
  Future<void> updateThemeFromImage(ImageProvider imageProvider) async {
    if (!_isDynamicThemeEnabled) return;
    
    try {
      final PaletteGenerator paletteGenerator = 
          await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: 20,
      );
      
      // Try to get a vibrant color first, fall back to dominant
      Color? newColor = paletteGenerator.vibrantColor?.color ??
          paletteGenerator.dominantColor?.color;
      
      if (newColor != null) {
        _seedColor = newColor;
        // Don't save to preferences - dynamic theme shouldn't override manual selection
        notifyListeners();
        debugPrint('Dynamic theme updated to: ${newColor.toString()}');
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
