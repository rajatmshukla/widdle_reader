import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A ChangeNotifier that manages the app's theme mode and seed color
class ThemeProvider extends ChangeNotifier {
  static const String _themePreferenceKey = 'theme_mode';
  static const String _seedColorKey = 'seed_color';

  /// Current theme mode (light, dark, or system)
  ThemeMode _themeMode = ThemeMode.system;

  /// Current seed color for generating the theme
  Color _seedColor = Colors.blue; // Default blue seed color

  /// Get the current theme mode
  ThemeMode get themeMode => _themeMode;

  /// Get the current seed color
  Color get seedColor => _seedColor;

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
}
