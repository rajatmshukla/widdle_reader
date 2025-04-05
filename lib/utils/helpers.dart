import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/audiobook.dart';
import '../providers/theme_provider.dart';

// Updated format duration to show hours and minutes only
String formatDuration(Duration? d) {
  if (d == null || d.inMilliseconds < 0) return '--:--';

  final int hours = d.inHours;
  final int minutes = (d.inMinutes % 60);

  if (hours > 0) {
    return '$hours hrs $minutes min';
  } else {
    return '$minutes min';
  }
}

// Enhanced cover widget with user's seed color and theme awareness
Widget buildCoverWidget(
  BuildContext context,
  Audiobook audiobook, {
  double size = 60.0,
  String? customTitle,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
  final seedColor = themeProvider.seedColor;

  if (audiobook.coverArt != null && audiobook.coverArt!.isNotEmpty) {
    return Image.memory(
      audiobook.coverArt!,
      width: size,
      height: size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        debugPrint("Error loading cover image for ${audiobook.title}: $error");
        return _buildDefaultCover(
          context,
          audiobook,
          size: size,
          seedColor: seedColor,
          customTitle: customTitle,
        );
      },
    );
  } else {
    return _buildDefaultCover(
      context,
      audiobook,
      size: size,
      seedColor: seedColor,
      customTitle: customTitle,
    );
  }
}

// Create a cute default cover with gradient derived from the seed color
Widget _buildDefaultCover(
  BuildContext context,
  Audiobook audiobook, {
  double size = 60.0,
  required Color seedColor,
  String? customTitle,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final title = customTitle ?? audiobook.title;
  final isDark = colorScheme.brightness == Brightness.dark;

  // Generate colors derived from the seed color
  final hslSeed = HSLColor.fromColor(seedColor);

  // Adjust luminance based on theme
  final double luminanceBase = isDark ? 0.3 : 0.5;
  final double luminanceAccent = isDark ? 0.2 : 0.7;

  // Create a color pair with complementary hues
  final baseColor = hslSeed.withLightness(luminanceBase).toColor();

  // Create accent color with adjusted hue (+40 degrees)
  final accentHue = (hslSeed.hue + 40) % 360;
  final accentColor =
      HSLColor.fromAHSL(
        1.0,
        accentHue,
        hslSeed.saturation,
        luminanceAccent,
      ).toColor();

  // First character for the cover
  final String coverChar = title.isNotEmpty ? title[0].toUpperCase() : '?';

  // Identify emoji if one exists in the title
  final RegExp emojiRegex = RegExp(
    r'(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])',
  );
  final Match? emojiMatch = emojiRegex.firstMatch(title);
  final String? emoji = emojiMatch?.group(0);

  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [baseColor, accentColor],
      ),
      borderRadius: BorderRadius.circular(size * 0.15),
      boxShadow: [
        BoxShadow(
          color: seedColor.withOpacity(0.4),
          blurRadius: 5,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Stack(
      children: [
        // Decorative elements
        Positioned(
          top: size * 0.1,
          right: size * 0.1,
          child: Icon(
            Icons.music_note,
            color: Colors.white.withOpacity(0.15),
            size: size * 0.2,
          ),
        ),
        Positioned(
          bottom: size * 0.1,
          left: size * 0.1,
          child: Icon(
            Icons.headphones,
            color: Colors.white.withOpacity(0.15),
            size: size * 0.2,
          ),
        ),

        // Display emoji or first character
        Center(
          child:
              emoji != null
                  ? Text(emoji, style: TextStyle(fontSize: size * 0.4))
                  : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        coverChar,
                        style: TextStyle(
                          fontSize: size * 0.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      if (size > 60)
                        SizedBox(
                          width: size * 0.8,
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: size * 0.08,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withOpacity(0.9),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
        ),
      ],
    ),
  );
}
