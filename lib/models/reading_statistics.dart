/// Model representing aggregated statistics for a single day
class DailyStats {
  final String date; // YYYY-MM-DD format
  final int totalSeconds; // Changed from minutes to seconds
  final int sessionCount;
  final int pagesRead;
  final Set<String> audiobooksRead; // Track which books were read
  final Map<String, int> bookDurations; // Track duration per book (BookId -> Seconds)

  DailyStats({
    required this.date,
    required this.totalSeconds,
    required this.sessionCount,
    required this.pagesRead,
    Set<String>? audiobooksRead,
    Map<String, int>? bookDurations,
  }) : audiobooksRead = audiobooksRead ?? {},
       bookDurations = bookDurations ?? {};

  /// Get total minutes (rounded)
  int get totalMinutes => (totalSeconds / 60).round();

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'totalSeconds': totalSeconds,
      'sessionCount': sessionCount,
      'pagesRead': pagesRead,
      'audiobooksRead': audiobooksRead.toList(),
      'bookDurations': bookDurations,
    };
  }

  /// Create from JSON
  factory DailyStats.fromJson(Map<String, dynamic> json) {
    // Handle migration
    int seconds;
    if (json.containsKey('totalSeconds')) {
      seconds = json['totalSeconds'] as int;
    } else {
      seconds = (json['totalMinutes'] as int) * 60;
    }

    // Handle bookDurations migration (if missing, empty map)
    Map<String, int> durations = {};
    if (json.containsKey('bookDurations')) {
      final Map<String, dynamic> rawMap = json['bookDurations'];
      durations = rawMap.map((key, value) => MapEntry(key, value as int));
    }

    return DailyStats(
      date: json['date'] as String,
      totalSeconds: seconds,
      sessionCount: json['sessionCount'] as int,
      pagesRead: json['pagesRead'] as int? ?? 0,
      audiobooksRead: Set<String>.from(json['audiobooksRead'] as List? ?? []),
      bookDurations: durations,
    );
  }

  /// Create empty stats for a date
  factory DailyStats.empty(String date) {
    return DailyStats(
      date: date,
      totalSeconds: 0,
      sessionCount: 0,
      pagesRead: 0,
      audiobooksRead: {},
      bookDurations: {},
    );
  }

  /// Get intensity level for heatmap (0-4)
  int get intensityLevel {
    if (totalMinutes == 0) return 0;
    if (totalMinutes <= 15) return 1;
    if (totalMinutes <= 30) return 2;
    if (totalMinutes <= 60) return 3;
    return 4; // 60+ minutes
  }

  /// Copy with updated values
  DailyStats copyWith({
    String? date,
    int? totalSeconds,
    int? sessionCount,
    int? pagesRead,
    Set<String>? audiobooksRead,
    Map<String, int>? bookDurations,
  }) {
    return DailyStats(
      date: date ?? this.date,
      totalSeconds: totalSeconds ?? this.totalSeconds,
      sessionCount: sessionCount ?? this.sessionCount,
      pagesRead: pagesRead ?? this.pagesRead,
      audiobooksRead: audiobooksRead ?? Set<String>.from(this.audiobooksRead),
      bookDurations: bookDurations ?? Map<String, int>.from(this.bookDurations),
    );
  }

  @override
  String toString() {
    return 'DailyStats(date: $date, seconds: $totalSeconds, sessions: $sessionCount, pages: $pagesRead)';
  }
}

/// Model for reading streaks
class ReadingStreak {
  final int currentStreak;
  final int longestStreak;
  final DateTime? lastReadDate;

  ReadingStreak({
    required this.currentStreak,
    required this.longestStreak,
    this.lastReadDate,
  });

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'currentStreak': currentStreak,
      'longestStreak': longestStreak,
      'lastReadDate': lastReadDate?.millisecondsSinceEpoch,
    };
  }

  /// Create from JSON
  factory ReadingStreak.fromJson(Map<String, dynamic> json) {
    return ReadingStreak(
      currentStreak: json['currentStreak'] as int,
      longestStreak: json['longestStreak'] as int,
      lastReadDate: json['lastReadDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastReadDate'] as int)
          : null,
    );
  }

  /// Create empty streak
  factory ReadingStreak.empty() {
    return ReadingStreak(
      currentStreak: 0,
      longestStreak: 0,
      lastReadDate: null,
    );
  }
}
