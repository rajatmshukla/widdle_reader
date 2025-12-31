import 'package:audio_service/audio_service.dart';

class Chapter {
  final String id; // Use file path as unique ID
  final String title;
  final String audiobookId; // Folder path
  final String sourcePath; // Path to the actual audio file
  Duration? duration; // To be loaded
  final Duration start;
  final Duration? end;

  Chapter({
    required this.id,
    required this.title,
    required this.audiobookId,
    required this.sourcePath,
    this.duration,
    this.start = Duration.zero,
    this.end,
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
        'sourcePath': sourcePath,
        'startMs': start.inMilliseconds,
        'endMs': end?.inMilliseconds,
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
      sourcePath: mediaItem.extras?['sourcePath'] ?? mediaItem.id,
      duration: mediaItem.duration,
      start: Duration(milliseconds: mediaItem.extras?['startMs'] ?? 0),
      end: mediaItem.extras?['endMs'] != null 
          ? Duration(milliseconds: mediaItem.extras!['endMs']) 
          : null,
    );
  }

  Chapter copyWith({
    String? id,
    String? title,
    String? audiobookId,
    String? sourcePath,
    Duration? duration,
    Duration? start,
    Duration? end,
  }) {
    return Chapter(
      id: id ?? this.id,
      title: title ?? this.title,
      audiobookId: audiobookId ?? this.audiobookId,
      sourcePath: sourcePath ?? this.sourcePath,
      duration: duration ?? this.duration,
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }
}
