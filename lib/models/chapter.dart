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

  MediaItem toMediaItem({String? audiobookTitle, String? audiobookAuthor, Uri? artUri}) {
    return MediaItem(
      id: id,
      album: audiobookTitle ?? audiobookId, // Store audiobookId here
      title: title,
      artist: audiobookAuthor,
      duration: duration,
      artUri: artUri, // Pass in the cover art URI
      displayTitle: title,
      displaySubtitle: audiobookTitle ?? audiobookId,
      extras: {
        'audiobookId': audiobookId,
        'audiobookTitle': audiobookTitle,
        'audiobookAuthor': audiobookAuthor,
      },
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
