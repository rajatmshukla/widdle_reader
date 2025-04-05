import 'package:flutter/material.dart';
import '../models/audiobook.dart';

String formatDuration(Duration? d) {
  // ... (function remains the same)
  if (d == null || d.inMilliseconds < 0) return '--:--';
  int totalSeconds = d.inSeconds;
  final int hours = totalSeconds ~/ 3600;
  final int minutes = (totalSeconds % 3600) ~/ 60;
  final int seconds = totalSeconds % 60;

  final String secondsStr = seconds.toString().padLeft(2, '0');
  final String minutesStr = minutes.toString().padLeft(2, '0');

  if (hours > 0) {
    final String hoursStr = hours.toString();
    return '$hoursStr:$minutesStr:$secondsStr';
  } else {
    return '$minutesStr:$secondsStr';
  }
}

// Needs BuildContext to call _buildDefaultCover which uses Theme.of(context)
Widget buildCoverWidget(
  BuildContext context,
  Audiobook audiobook, {
  double size = 60.0,
}) {
  if (audiobook.coverArt != null && audiobook.coverArt!.isNotEmpty) {
    return Image.memory(
      audiobook.coverArt!,
      width: size,
      height: size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        debugPrint("Error loading cover image for ${audiobook.title}: $error");
        // Pass context here
        return _buildDefaultCover(context, audiobook, size: size);
      },
    );
  } else {
    // Pass context here
    return _buildDefaultCover(context, audiobook, size: size);
  }
}

Widget _buildDefaultCover(
  BuildContext context,
  Audiobook audiobook, {
  double size = 60.0,
}) {
  final theme = Theme.of(context); // context is now defined
  return Container(
    width: size,
    height: size,
    color:
        theme.colorScheme.primaryContainer.withAlpha((255 * 0.3).round()) ??
        Colors.grey[800], // Keep ?. check
    child: Center(
      child: Text(
        audiobook.title.isNotEmpty ? audiobook.title[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: size * 0.5,
          color:
              theme.textTheme.bodyLarge?.color?.withAlpha(
                (255 * 0.6).round(),
              ) ??
              Colors.white70, // Keep ?. checks
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );
}
