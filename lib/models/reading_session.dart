/// Model representing a single reading session
class ReadingSession {
  final String sessionId; // Timestamp-based unique ID
  final String audiobookId;
  final DateTime startTime;
  final DateTime endTime;
  final int durationSeconds; // Changed from minutes to seconds for precision
  final int pagesRead; // Number of chapters progressed
  final String? chapterName; // Optional chapter name for context

  ReadingSession({
    required this.sessionId,
    required this.audiobookId,
    required this.startTime,
    required this.endTime,
    required this.durationSeconds,
    this.pagesRead = 0,
    this.chapterName,
  });

  /// Get duration in minutes (rounded)
  int get durationMinutes => (durationSeconds / 60).round();

  /// Calculate duration from start/end times
  factory ReadingSession.fromTimes({
    required String audiobookId,
    required DateTime startTime,
    required DateTime endTime,
    int pagesRead = 0,
    String? chapterName,
    String? sessionId, // Allow passing ID for continuous updates
  }) {
    final durationSec = endTime.difference(startTime).inSeconds;
    final id = sessionId ?? '${startTime.millisecondsSinceEpoch}';
    
    return ReadingSession(
      sessionId: id,
      audiobookId: audiobookId,
      startTime: startTime,
      endTime: endTime,
      durationSeconds: durationSec < 0 ? 0 : durationSec,
      pagesRead: pagesRead,
      chapterName: chapterName,
    );
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'audiobookId': audiobookId,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime.millisecondsSinceEpoch,
      'durationSeconds': durationSeconds,
      'pagesRead': pagesRead,
      'chapterName': chapterName,
    };
  }

  /// Create from JSON
  factory ReadingSession.fromJson(Map<String, dynamic> json) {
    // Handle migration from old minutes-based data
    int seconds;
    if (json.containsKey('durationSeconds')) {
      seconds = json['durationSeconds'] as int;
    } else {
      seconds = (json['durationMinutes'] as int) * 60;
    }

    return ReadingSession(
      sessionId: json['sessionId'] as String,
      audiobookId: json['audiobookId'] as String,
      startTime: DateTime.fromMillisecondsSinceEpoch(json['startTime'] as int),
      endTime: DateTime.fromMillisecondsSinceEpoch(json['endTime'] as int),
      durationSeconds: seconds,
      pagesRead: json['pagesRead'] as int? ?? 0,
      chapterName: json['chapterName'] as String?,
    );
  }

  /// Get the date string for this session (YYYY-MM-DD)
  String get dateString {
    final date = startTime;
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  String toString() {
    return 'ReadingSession(id: $sessionId, book: $audiobookId, duration: ${durationSeconds}s, date: $dateString)';
  }
}
