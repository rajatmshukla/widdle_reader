import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import '../services/simple_audio_service.dart';

class PlayerControls extends StatelessWidget {
  // Make audioHandler required and use the specific type
  final SimpleAudioService audioHandler;
  final PlaybackState state;
  final MediaItem? mediaItem;

  const PlayerControls({
    // Use super parameters
    super.key,
    required this.audioHandler,
    required this.state,
    this.mediaItem,
  });

  @override
  Widget build(BuildContext context) {
    final bool isPlaying = state.playing;
    final bool hasItem = mediaItem != null;
    final bool isLoading =
        state.processingState == AudioProcessingState.loading ||
        state.processingState == AudioProcessingState.buffering;

    // Use MediaQuery to adjust layout based on orientation
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final iconSize =
        isLandscape ? 36.0 : 42.0; // Slightly smaller icons in landscape
    final playPauseSize =
        isLandscape ? 56.0 : 64.0; // Smaller play/pause button in landscape

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Rewind Button
        IconButton(
          icon: const Icon(Icons.replay), // Changed to 15 seconds icon
          iconSize: iconSize,
          tooltip: "Rewind 30 seconds",
          // Disable if no item or loading
          onPressed: hasItem && !isLoading ? audioHandler.rewind : null,
          disabledColor: Colors.grey[700],
        ),

        // Previous Button
        IconButton(
          icon: const Icon(Icons.skip_previous),
          iconSize: iconSize,
          tooltip: "Previous Chapter",
          // Disable if no item or loading
          onPressed: hasItem && !isLoading ? audioHandler.skipToPrevious : null,
          disabledColor: Colors.grey[700],
        ),

        // Play/Pause/Loading Button
        _buildPlayPauseButton(isPlaying, isLoading, hasItem, playPauseSize),

        // Next Button
        IconButton(
          icon: const Icon(Icons.skip_next),
          iconSize: iconSize,
          tooltip: "Next Chapter",
          // Disable if no item or loading
          onPressed: hasItem && !isLoading ? audioHandler.skipToNext : null,
          disabledColor: Colors.grey[700],
        ),

        // Forward Button
        IconButton(
          icon: const Icon(Icons.forward), // Changed to 15 seconds icon
          iconSize: iconSize,
          tooltip: "Forward 30 seconds",
          // Disable if no item or loading
          onPressed: hasItem && !isLoading ? audioHandler.fastForward : null,
          disabledColor: Colors.grey[700],
        ),
      ],
    );
  }

  // Helper to build the central button with loading state
  Widget _buildPlayPauseButton(
    bool isPlaying,
    bool isLoading,
    bool hasItem,
    double size,
  ) {
    if (isLoading) {
      return Container(
        margin: const EdgeInsets.all(8.0), // Match IconButton padding roughly
        width: size,
        height: size,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 3.0)),
      );
    } else {
      return IconButton(
        icon: Icon(
          isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
        ),
        iconSize: size, // Use responsive size
        tooltip: isPlaying ? "Pause" : "Play",
        // Disable only if no item
        onPressed:
            hasItem
                ? (isPlaying ? audioHandler.pause : audioHandler.play)
                : null,
        disabledColor: Colors.grey[700],
      );
    }
  }
}
