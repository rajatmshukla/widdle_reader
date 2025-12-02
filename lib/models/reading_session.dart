/// Model representing a single reading session
class ReadingSession {
  final String sessionId; // Timestamp-based unique ID
  final String audiobookId;
  final DateTime startTime;
  final DateTime endTime;
  final int durationMinutes;
  final int pagesRead; // Number of chapters progressed
  final String? chapterName; // Optional chapter name for context

  ReadingSession({
    required this.sessionId,
    required this.audiobookId,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    this.pagesRead = 0,
    this.chapterName,
  });

  /// Calculate duration from start/end times
  factory ReadingSession.fromTimes({
    required String audiobookId,
    required DateTime startTime,
    required DateTime endTime,
    int pagesRead = 0,
    String? chapterName,
  }) {
    final duration = endTime.difference(startTime).inMinutes;
    final sessionId = '${startTime.millisecondsSinceEpoch}';
    
    return ReadingSession(
      sessionId: sessionId,
      audiobookId: audiobookId,
      startTime: startTime,
      endTime: endTime,
      durationMinutes: duration.clamp(0, 1440), // Max 24 hours
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
      'durationMinutes': durationMinutes,
      'pagesRead': pagesRead,
      'chapterName': chapterName,
    };
  }

  /// Create from JSON
  factory ReadingSession.fromJson(Map<String, dynamic> json) {
    return ReadingSession(
      sessionId: json['sessionId'] as String,
      audiobookId: json['audiobookId'] as String,
      startTime: DateTime.fromMillisecondsSinceEpoch(json['startTime'] as int),
      endTime: DateTime.fromMillisecondsSinceEpoch(json['endTime'] as int),
      durationMinutes: json['durationMinutes'] as int,
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
    return 'ReadingSession(id: $sessionId, book: $audiobookId, duration: ${durationMinutes}min, date: $dateString)';
  }
}
