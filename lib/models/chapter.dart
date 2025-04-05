import 'package:audio_service/audio_service.dart';

class Chapter {
  final String id; // Use file path as unique ID
  final String title;
  final String audiobookId; // Folder path
  Duration? duration; // To be loaded

  Chapter({
    required this.id,
    required this.title,
    required this.audiobookId,
    this.duration,
  });

  MediaItem toMediaItem() {
    return MediaItem(
      id: id,
      album: audiobookId, // Store audiobookId here
      title: title,
      duration: duration,
      artUri: null, // We'll handle art at the Audiobook level for now
      extras: {'audiobookId': audiobookId}, // Store original id if needed
    );
  }

  static Chapter fromMediaItem(MediaItem mediaItem) {
    return Chapter(
      id: mediaItem.id,
      title: mediaItem.title,
      audiobookId:
          mediaItem.album ??
          mediaItem.extras?['audiobookId'] ??
          'Unknown Audiobook',
      duration: mediaItem.duration,
    );
  }
}
