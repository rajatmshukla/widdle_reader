import 'package:flutter/material.dart';
import '../services/statistics_service.dart';
import '../models/reading_session.dart';

/// Service for analyzing reading patterns and generating personality insights
class PersonalityService {
  static final PersonalityService _instance = PersonalityService._internal();
  factory PersonalityService() => _instance;
  PersonalityService._internal();

  final StatisticsService _statsService = StatisticsService();

  /// Analyze reading patterns and return a personality profile
  Future<ReadingPersonality> analyzePersonality({Map<String, Set<String>>? bookTags}) async {
    final sessions = await _statsService.getRecentSessions(200); // More data for better insights
    final streak = await _statsService.getStreak();

    if (sessions.isEmpty) {
      return ReadingPersonality.empty();
    }

    // Analyze time preferences
    final timePreference = _analyzeTimePreference(sessions);
    
    // Analyze session patterns
    final sessionPattern = _analyzeSessionPattern(sessions);
    
    // Calculate consistency score
    final consistencyScore = _calculateConsistency(sessions, streak.currentStreak);

    // Calculate stability score (how regular the start times are)
    final stabilityScore = _calculateStability(sessions);
    
    // Calculate average session duration
    final avgSessionMinutes = sessions.isEmpty
        ? 0.0
        : sessions.fold<int>(0, (sum, s) => sum + s.durationMinutes) / sessions.length;

    // Analyze genres if tags are provided
    Map<String, double> genreDistribution = {};
    if (bookTags != null) {
      genreDistribution = _analyzeGenres(sessions, bookTags);
    }
    
    // Determine personality type
    final personalityType = _determinePersonalityType(
      timePreference: timePreference,
      sessionPattern: sessionPattern,
      consistencyScore: consistencyScore,
      stabilityScore: stabilityScore,
      avgSessionMinutes: avgSessionMinutes,
      genreDistribution: genreDistribution,
      sessions: sessions,
    );

    return ReadingPersonality(
      type: personalityType,
      timePreference: timePreference,
      sessionPattern: sessionPattern,
      consistencyScore: consistencyScore,
      stabilityScore: stabilityScore,
      avgSessionMinutes: avgSessionMinutes,
      currentStreak: streak.currentStreak,
      totalSessions: sessions.length,
      genreDistribution: genreDistribution,
    );
  }

  /// Analyze preferred reading times
  TimePreference _analyzeTimePreference(List<ReadingSession> sessions) {
    int morningCount = 0; // 5-11
    int afternoonCount = 0; // 12-17
    int eveningCount = 0; // 18-21
    int nightCount = 0; // 22-4

    for (final session in sessions) {
      final hour = session.startTime.hour;
      if (hour >= 5 && hour < 12) {
        morningCount++;
      } else if (hour >= 12 && hour < 18) {
        afternoonCount++;
      } else if (hour >= 18 && hour < 22) {
        eveningCount++;
      } else {
        nightCount++;
      }
    }

    final counts = {
      TimePreference.earlyBird: morningCount,
      TimePreference.afternoonReader: afternoonCount,
      TimePreference.eveningEnthusiast: eveningCount,
      TimePreference.nightOwl: nightCount,
    };

    return counts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  /// Analyze session patterns
  SessionPattern _analyzeSessionPattern(List<ReadingSession> sessions) {
    if (sessions.isEmpty) return SessionPattern.casual;

    final avgDuration = sessions.fold<int>(0, (sum, s) => sum + s.durationMinutes) / sessions.length;
    final sessionsPerDay = _getSessionsPerDay(sessions);

    if (avgDuration >= 60 && sessionsPerDay < 2) {
      return SessionPattern.marathon;
    } else if (avgDuration < 20 && sessionsPerDay >= 2) {
      return SessionPattern.snacker;
    } else if (avgDuration >= 30 && avgDuration < 60) {
      return SessionPattern.balanced;
    } else {
      return SessionPattern.casual;
    }
  }

  double _getSessionsPerDay(List<ReadingSession> sessions) {
    if (sessions.isEmpty) return 0;
    final uniqueDays = sessions.map((s) => s.dateString).toSet().length;
    return sessions.length / uniqueDays;
  }

  /// Calculate consistency score (0-100)
  double _calculateConsistency(List<ReadingSession> sessions, int streak) {
    if (sessions.isEmpty) return 0;
    final streakScore = (streak / 30).clamp(0.0, 1.0) * 40;
    final uniqueDays = sessions.map((s) => s.dateString).toSet().length;
    
    final daysCovered = sessions.isNotEmpty 
        ? DateTime.now().difference(sessions.last.startTime).inDays + 1
        : 1;
    final regularityScore = (uniqueDays / daysCovered.clamp(1, 30)) * 60;

    return (streakScore + regularityScore).clamp(0, 100);
  }

  /// Calculate stability (how predictable the start times are)
  double _calculateStability(List<ReadingSession> sessions) {
    if (sessions.length < 5) return 0;
    
    // Group sessions by weekday to see if user has a routine
    final Map<int, List<int>> hourByDay = {};
    for (var session in sessions) {
      final day = session.startTime.weekday;
      final hour = session.startTime.hour;
      hourByDay.putIfAbsent(day, () => []).add(hour);
    }

    double totalVariance = 0;
    int count = 0;

    for (var hours in hourByDay.values) {
      if (hours.length < 2) continue;
      final mean = hours.reduce((a, b) => a + b) / hours.length;
      final variance = hours.map((h) => (h - mean) * (h - mean)).reduce((a, b) => a + b) / hours.length;
      totalVariance += variance;
      count++;
    }

    if (count == 0) return 0;
    final avgVariance = totalVariance / count;
    
    // Low variance = high stability
    // 0 variance = 100 score, >16 variance (4 hours std dev) = 0 score
    return (100 - (avgVariance * 6.25)).clamp(0, 100);
  }

  /// Analyze genre distribution
  Map<String, double> _analyzeGenres(List<ReadingSession> sessions, Map<String, Set<String>> bookTags) {
    final Map<String, int> durationByTag = {};
    int totalDuration = 0;

    for (var session in sessions) {
      final tags = bookTags[session.audiobookId] ?? {'Uncategorized'};
      for (var tag in tags) {
        durationByTag[tag] = (durationByTag[tag] ?? 0) + session.durationSeconds;
      }
      totalDuration += session.durationSeconds;
    }

    if (totalDuration == 0) return {};

    return durationByTag.map((tag, duration) => MapEntry(tag, duration / totalDuration));
  }

  /// Determine personality type based on all factors
  PersonalityType _determinePersonalityType({
    required TimePreference timePreference,
    required SessionPattern sessionPattern,
    required double consistencyScore,
    required double stabilityScore,
    required double avgSessionMinutes,
    required Map<String, double> genreDistribution,
    required List<ReadingSession> sessions,
  }) {
    // 1. Clockwork: Extremely stable start times
    if (stabilityScore >= 85 && sessions.length >= 10) {
      return PersonalityType.clockwork;
    }

    // 2. Dedicated: High consistency
    if (consistencyScore >= 75) {
      return PersonalityType.dedicated;
    }

    // 3. Weekend Warrior: Concentrated on weekends
    final weekendSessions = sessions.where((s) => s.startTime.weekday >= 6).length;
    if (weekendSessions / sessions.length > 0.6 && sessions.length >= 5) {
      return PersonalityType.weekendWarrior;
    }

    // 4. Specialist: High concentration in one genre
    if (genreDistribution.values.any((v) => v >= 0.7)) {
      return PersonalityType.specialist;
    }

    // 5. Deep Diver: Marathon sessions
    if (sessionPattern == SessionPattern.marathon && avgSessionMinutes >= 45) {
      return PersonalityType.deepDiver;
    }

    // 6. Scholar: Night owls with consistent reading
    if (timePreference == TimePreference.nightOwl && consistencyScore >= 40) {
      return PersonalityType.scholar;
    }

    // 7. Multitasker: Snackers
    if (sessionPattern == SessionPattern.snacker) {
      return PersonalityType.multitasker;
    }

    // 8. Sunrise Reader
    if (timePreference == TimePreference.earlyBird) {
      return PersonalityType.sunriseReader;
    }

    return PersonalityType.explorer;
  }
}

/// Reading personality profile
class ReadingPersonality {
  final PersonalityType type;
  final TimePreference timePreference;
  final SessionPattern sessionPattern;
  final double consistencyScore;
  final double stabilityScore;
  final double avgSessionMinutes;
  final int currentStreak;
  final int totalSessions;
  final Map<String, double> genreDistribution;

  const ReadingPersonality({
    required this.type,
    required this.timePreference,
    required this.sessionPattern,
    required this.consistencyScore,
    required this.stabilityScore,
    required this.avgSessionMinutes,
    required this.currentStreak,
    required this.totalSessions,
    required this.genreDistribution,
  });

  factory ReadingPersonality.empty() {
    return const ReadingPersonality(
      type: PersonalityType.explorer,
      timePreference: TimePreference.afternoonReader,
      sessionPattern: SessionPattern.casual,
      consistencyScore: 0,
      stabilityScore: 0,
      avgSessionMinutes: 0,
      currentStreak: 0,
      totalSessions: 0,
      genreDistribution: {},
    );
  }

  bool get isEmpty => totalSessions == 0;
}

/// Personality types
enum PersonalityType {
  deepDiver,
  scholar,
  multitasker,
  sunriseReader,
  dedicated,
  explorer,
  clockwork,
  weekendWarrior,
  specialist,
}

extension PersonalityTypeExt on PersonalityType {
  String get name {
    switch (this) {
      case PersonalityType.deepDiver: return 'Deep Diver';
      case PersonalityType.scholar: return 'Late Night Scholar';
      case PersonalityType.multitasker: return 'Multitasker';
      case PersonalityType.sunriseReader: return 'Sunrise Reader';
      case PersonalityType.dedicated: return 'Dedicated Listener';
      case PersonalityType.explorer: return 'Explorer';
      case PersonalityType.clockwork: return 'Clockwork Reader';
      case PersonalityType.weekendWarrior: return 'Weekend Warrior';
      case PersonalityType.specialist: return 'Genre Specialist';
    }
  }

  String get description {
    switch (this) {
      case PersonalityType.deepDiver:
        return 'You love long, immersive listening sessions. Once you start, you\'re fully absorbed in the story.';
      case PersonalityType.scholar:
        return 'The quiet night hours are your domain. You find peace in late-night reading sessions.';
      case PersonalityType.multitasker:
        return 'Quick sessions throughout the day keep you engaged. You maximize every spare moment.';
      case PersonalityType.sunriseReader:
        return 'Early mornings are your reading time. You start your day with audiobooks.';
      case PersonalityType.dedicated:
        return 'Consistency is your superpower. Your daily reading habit is truly impressive.';
      case PersonalityType.explorer:
        return 'You\'re exploring various styles and genres. Keep listening to build your unique profile.';
      case PersonalityType.clockwork:
        return 'Your routine is incredibly precise. You listen at the exact same time, every day.';
      case PersonalityType.weekendWarrior:
        return 'You save your biggest listening adventures for the weekend when you can truly dive in.';
      case PersonalityType.specialist:
        return 'You know what you like and you stick to it. You\'ve mastered your favorite genre.';
    }
  }

  IconData get icon {
    switch (this) {
      case PersonalityType.deepDiver: return Icons.scuba_diving;
      case PersonalityType.scholar: return Icons.school;
      case PersonalityType.multitasker: return Icons.bolt;
      case PersonalityType.sunriseReader: return Icons.wb_sunny;
      case PersonalityType.dedicated: return Icons.star;
      case PersonalityType.explorer: return Icons.explore;
      case PersonalityType.clockwork: return Icons.update;
      case PersonalityType.weekendWarrior: return Icons.hiking;
      case PersonalityType.specialist: return Icons.psychology;
    }
  }

  Color get color {
    switch (this) {
      case PersonalityType.deepDiver: return const Color(0xFF1E88E5);
      case PersonalityType.scholar: return const Color(0xFF5E35B1);
      case PersonalityType.multitasker: return const Color(0xFFFF9800);
      case PersonalityType.sunriseReader: return const Color(0xFFFFB300);
      case PersonalityType.dedicated: return const Color(0xFF43A047);
      case PersonalityType.explorer: return const Color(0xFF00ACC1);
      case PersonalityType.clockwork: return const Color(0xFF7CB342);
      case PersonalityType.weekendWarrior: return const Color(0xFFE53935);
      case PersonalityType.specialist: return const Color(0xFFD81B60);
    }
  }
}

/// Time preference
enum TimePreference {
  earlyBird,
  afternoonReader,
  eveningEnthusiast,
  nightOwl,
}

extension TimePreferenceExt on TimePreference {
  String get name {
    switch (this) {
      case TimePreference.earlyBird: return 'Early Bird';
      case TimePreference.afternoonReader: return 'Afternoon Reader';
      case TimePreference.eveningEnthusiast: return 'Evening Enthusiast';
      case TimePreference.nightOwl: return 'Night Owl';
    }
  }

  IconData get icon {
    switch (this) {
      case TimePreference.earlyBird: return Icons.wb_sunny;
      case TimePreference.afternoonReader: return Icons.wb_twilight;
      case TimePreference.eveningEnthusiast: return Icons.nights_stay;
      case TimePreference.nightOwl: return Icons.dark_mode;
    }
  }
}

/// Session patterns
enum SessionPattern {
  marathon,
  snacker,
  balanced,
  casual,
}

extension SessionPatternExt on SessionPattern {
  String get name {
    switch (this) {
      case SessionPattern.marathon: return 'Marathons';
      case SessionPattern.snacker: return 'Snacker';
      case SessionPattern.balanced: return 'Balanced';
      case SessionPattern.casual: return 'Casual';
    }
  }
}
