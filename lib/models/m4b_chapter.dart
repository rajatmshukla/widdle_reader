import 'package:audio_service/audio_service.dart';

/// Model for M4B embedded chapters with timestamp-based navigation
class M4BChapter {
  final String id;
  final String title;
  final Duration startTime; // When this chapter starts in the file
  final Duration duration;  // Duration of this chapter
  final String audiobookId; // Reference to the M4B file path

  M4BChapter({
    required this.id,
    required this.title,
    required this.startTime,
    required this.duration,
    required this.audiobookId,
  });

  /// Get the end time of this chapter
  Duration get endTime => startTime + duration;

  /// Copy method for updating chapter properties
  M4BChapter copyWith({
    String? id,
    String? title,
    Duration? startTime,
    Duration? duration,
    String? audiobookId,
  }) {
    return M4BChapter(
      id: id ?? this.id,
      title: title ?? this.title,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      audiobookId: audiobookId ?? this.audiobookId,
    );
  }

  /// Convert to MediaItem for audio service
  MediaItem toMediaItem({
    String? audiobookTitle,
    String? audiobookAuthor,
    Uri? artUri,
  }) {
    return MediaItem(
      id: id,
      album: audiobookTitle ?? audiobookId,
      title: title,
      artist: audiobookAuthor,
      duration: duration,
      artUri: artUri,
      displayTitle: title,
      displaySubtitle: audiobookTitle ?? audiobookId,
      extras: {
        'audiobookId': audiobookId,
        'audiobookTitle': audiobookTitle,
        'audiobookAuthor': audiobookAuthor,
        'startTime': startTime.inMilliseconds,
        'isM4BChapter': true, // Flag to identify M4B chapters
      },
    );
  }

  /// Create from MediaItem
  static M4BChapter fromMediaItem(MediaItem mediaItem) {
    final startTimeMs = mediaItem.extras?['startTime'] as int? ?? 0;
    
    return M4BChapter(
      id: mediaItem.id,
      title: mediaItem.title,
      startTime: Duration(milliseconds: startTimeMs),
      duration: mediaItem.duration ?? Duration.zero,
      audiobookId: mediaItem.album ?? 
                   mediaItem.extras?['audiobookId'] ?? 
                   'Unknown Audiobook',
    );
  }

  /// Check if this chapter contains a specific timestamp
  bool containsTimestamp(Duration timestamp) {
    return timestamp >= startTime && timestamp < endTime;
  }

  @override
  String toString() {
    return 'M4BChapter(id: $id, title: $title, startTime: $startTime, duration: $duration)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is M4BChapter &&
        other.id == id &&
        other.title == title &&
        other.startTime == startTime &&
        other.duration == duration &&
        other.audiobookId == audiobookId;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        title.hashCode ^
        startTime.hashCode ^
        duration.hashCode ^
        audiobookId.hashCode;
  }
} 