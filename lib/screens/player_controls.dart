import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import '../services/audio_handler.dart'; // <-- Added import for MyAudioHandler

class PlayerControls extends StatelessWidget {
  // Make audioHandler required and use the specific type
  final MyAudioHandler audioHandler;
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

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Rewind Button
        IconButton(
          icon: const Icon(Icons.replay), // Changed to 15 seconds icon
          iconSize: 42.0,
          tooltip: "Rewind 30 seconds",
          // Disable if no item or loading
          onPressed: hasItem && !isLoading ? audioHandler.rewind : null,
          disabledColor: Colors.grey[700],
        ),

        // Previous Button
        IconButton(
          icon: const Icon(Icons.skip_previous),
          iconSize: 42.0,
          tooltip: "Previous Chapter",
          // Disable if no item or loading
          onPressed: hasItem && !isLoading ? audioHandler.skipToPrevious : null,
          disabledColor: Colors.grey[700],
        ),

        // Play/Pause/Loading Button
        _buildPlayPauseButton(isPlaying, isLoading, hasItem),

        // Next Button
        IconButton(
          icon: const Icon(Icons.skip_next),
          iconSize: 42.0,
          tooltip: "Next Chapter",
          // Disable if no item or loading
          onPressed: hasItem && !isLoading ? audioHandler.skipToNext : null,
          disabledColor: Colors.grey[700],
        ),

        // Forward Button
        IconButton(
          icon: const Icon(Icons.forward), // Changed to 15 seconds icon
          iconSize: 42.0,
          tooltip: "Forward 30 seconds",
          // Disable if no item or loading
          onPressed: hasItem && !isLoading ? audioHandler.fastForward : null,
          disabledColor: Colors.grey[700],
        ),
      ],
    );
  }

  // Helper to build the central button with loading state
  Widget _buildPlayPauseButton(bool isPlaying, bool isLoading, bool hasItem) {
    if (isLoading) {
      return Container(
        margin: const EdgeInsets.all(8.0), // Match IconButton padding roughly
        width: 64.0,
        height: 64.0,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 3.0)),
      );
    } else {
      return IconButton(
        icon: Icon(
          isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
        ),
        iconSize: 64.0, // Larger central button
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
