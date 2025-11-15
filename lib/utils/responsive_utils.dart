import 'package:flutter/material.dart';

/// Utility class for responsive layouts
class ResponsiveUtils {
  /// Returns whether the current orientation is landscape
  static bool isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  /// Returns whether the current orientation is portrait
  static bool isPortrait(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.portrait;
  }

  /// Returns whether the current device is a tablet (based on screen size)
  static bool isTablet(BuildContext context) {
    // Consider devices with shortest side > 600dp as tablets
    return MediaQuery.of(context).size.shortestSide > 600;
  }

  /// Returns a value based on orientation
  static T orientationValue<T>(
    BuildContext context, {
    required T portrait,
    required T landscape,
  }) {
    return isLandscape(context) ? landscape : portrait;
  }

  /// Returns a layout based on orientation
  static Widget orientationWidget(
    BuildContext context, {
    required Widget portrait,
    required Widget landscape,
  }) {
    return isLandscape(context) ? landscape : portrait;
  }

  /// Returns a constraint-based layout (useful for limiting width in landscapes)
  static Widget constrainedWidth(
    BuildContext context, {
    required Widget child,
    double maxPortraitWidth = double.infinity,
    double maxLandscapeWidth = double.infinity,
  }) {
    final maxWidth =
        isLandscape(context) ? maxLandscapeWidth : maxPortraitWidth;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }

  /// Get a responsive padding based on screen size and orientation
  static EdgeInsets responsivePadding(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final horizontal = size.width * 0.05; // 5% of screen width
    final vertical = size.height * 0.02; // 2% of screen height

    return EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical);
  }

  /// Calculate a responsive font size based on screen width
  static double responsiveFontSize(
    BuildContext context, {
    required double baseFontSize,
    double minFontSize = 12.0,
    double maxFontSize = 24.0,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final fontSize =
        baseFontSize * screenWidth / 375.0; // Scale based on iPhone 8

    return fontSize.clamp(minFontSize, maxFontSize);
  }
}

/// Extension methods for BuildContext to make responsive utilities easier to use
extension ResponsiveContext on BuildContext {
  /// Check if the orientation is landscape
  bool get isLandscape => ResponsiveUtils.isLandscape(this);

  /// Check if the orientation is portrait
  bool get isPortrait => ResponsiveUtils.isPortrait(this);

  /// Check if the device is a tablet
  bool get isTablet => ResponsiveUtils.isTablet(this);

  /// Get screen size
  Size get screenSize => MediaQuery.of(this).size;

  /// Get responsive padding
  EdgeInsets get responsivePadding => ResponsiveUtils.responsivePadding(this);

  /// Get a value based on orientation
  T whenOrientation<T>({required T portrait, required T landscape}) {
    return ResponsiveUtils.orientationValue(
      this,
      portrait: portrait,
      landscape: landscape,
    );
  }
}
