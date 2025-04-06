import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Defines the app's cute theme styles
class AppTheme {
  /// Creates a light theme with the given seed color
  static ThemeData lightTheme(Color seedColor) {
    // Define base color scheme with the provided seed color
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );

    // Create Comfortaa text theme
    final textTheme = GoogleFonts.comfortaaTextTheme(
      ThemeData.light().textTheme,
    );

    return _createTheme(colorScheme, textTheme);
  }

  /// Creates a dark theme with the given seed color
  static ThemeData darkTheme(Color seedColor) {
    // Define base color scheme with the provided seed color
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );

    // Create Comfortaa text theme
    final textTheme = GoogleFonts.comfortaaTextTheme(
      ThemeData.dark().textTheme,
    );

    return _createTheme(colorScheme, textTheme);
  }

  /// Common theme creation for both light and dark themes
  static ThemeData _createTheme(ColorScheme colorScheme, TextTheme textTheme) {
    return ThemeData(
      // Enable Material 3
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: textTheme,

      // Scaffold background (slightly different from basic surface)
      scaffoldBackgroundColor: colorScheme.surface,

      // Custom app bar theme with rounded edges
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface.withOpacity(0.7),
        centerTitle: true,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),

      // Card theme with strong rounded corners
      cardTheme: CardTheme(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.7),
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        clipBehavior: Clip.antiAlias,
      ),

      // Dialog theme with cute rounded edges
      dialogTheme: DialogTheme(
        backgroundColor: colorScheme.surface,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),

      // Bottom sheet theme with rounded top edges
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        modalBackgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        clipBehavior: Clip.antiAlias,
        elevation: 8,
      ),

      // Text button theme with rounded shape
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // Elevated button theme with shadow
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 4,
          shadowColor: colorScheme.shadow.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // Floating action button theme with shadow
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        extendedPadding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 12,
        ),
      ),

      // List tile theme with rounded edges
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        tileColor: Colors.transparent,
        iconColor: colorScheme.primary,
      ),

      // Icon theme
      iconTheme: IconThemeData(color: colorScheme.onSurface, size: 24),

      // Slider theme for audio player
      sliderTheme: SliderThemeData(
        activeTrackColor: colorScheme.primary,
        inactiveTrackColor: colorScheme.onSurface.withOpacity(0.2),
        thumbColor: colorScheme.primary,
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 8,
          elevation: 4,
          pressedElevation: 8,
        ),
        trackHeight: 4,
        overlayColor: colorScheme.primary.withOpacity(0.2),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      ),

      // Input decoration theme
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.4),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),

      // Progress indicator theme
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        circularTrackColor: colorScheme.onSurface.withOpacity(0.1),
        linearTrackColor: colorScheme.onSurface.withOpacity(0.1),
      ),

      // Switch theme
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.surfaceContainerHighest;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary.withOpacity(0.5);
          }
          return colorScheme.onSurface.withOpacity(0.3);
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      // Divider theme
      dividerTheme: DividerThemeData(
        color: colorScheme.outline.withOpacity(0.3),
        thickness: 1,
        space: 24,
      ),

      // Popup menu theme
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surface,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  /// Creates a gradient background for screens based on the current theme
  static BoxDecoration gradientBackground(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool isDark = colorScheme.brightness == Brightness.dark;

    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          isDark
              ? colorScheme.primary.withOpacity(0.2)
              : colorScheme.primary.withOpacity(0.1),
          colorScheme.surface,
        ],
        stops: const [0.3, 1.0],
      ),
    );
  }
}
