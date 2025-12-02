/// Model representing aggregated statistics for a single day
class DailyStats {
  final String date; // YYYY-MM-DD format
  final int totalMinutes;
  final int sessionCount;
  final int pagesRead;
  final Set<String> audiobooksRead; // Track which books were read

  DailyStats({
    required this.date,
    required this.totalMinutes,
    required this.sessionCount,
    required this.pagesRead,
    Set<String>? audiobooksRead,
  }) : audiobooksRead = audiobooksRead ?? {};

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'totalMinutes': totalMinutes,
      'sessionCount': sessionCount,
      'pagesRead': pagesRead,
      'audiobooksRead': audiobooksRead.toList(),
    };
  }

  /// Create from JSON
  factory DailyStats.fromJson(Map<String, dynamic> json) {
    return DailyStats(
      date: json['date'] as String,
      totalMinutes: json['totalMinutes'] as int,
      sessionCount: json['sessionCount'] as int,
      pagesRead: json['pagesRead'] as int? ?? 0,
      audiobooksRead: Set<String>.from(json['audiobooksRead'] as List? ?? []),
    );
  }

  /// Create empty stats for a date
  factory DailyStats.empty(String date) {
    return DailyStats(
      date: date,
      totalMinutes: 0,
      sessionCount: 0,
      pagesRead: 0,
      audiobooksRead: {},
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
    int? totalMinutes,
    int? sessionCount,
    int? pagesRead,
    Set<String>? audiobooksRead,
  }) {
    return DailyStats(
      date: date ?? this.date,
      totalMinutes: totalMinutes ?? this.totalMinutes,
      sessionCount: sessionCount ?? this.sessionCount,
      pagesRead: pagesRead ?? this.pagesRead,
      audiobooksRead: audiobooksRead ?? Set<String>.from(this.audiobooksRead),
    );
  }

  @override
  String toString() {
    return 'DailyStats(date: $date, minutes: $totalMinutes, sessions: $sessionCount, pages: $pagesRead)';
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
