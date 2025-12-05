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
  Future<ReadingPersonality> analyzePersonality() async {
    final sessions = await _statsService.getRecentSessions(100);
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
    
    // Calculate average session duration
    final avgSessionMinutes = sessions.isEmpty
        ? 0.0
        : sessions.fold<int>(0, (sum, s) => sum + s.durationMinutes) / sessions.length;
    
    // Determine personality type
    final personalityType = _determinePersonalityType(
      timePreference: timePreference,
      sessionPattern: sessionPattern,
      consistencyScore: consistencyScore,
      avgSessionMinutes: avgSessionMinutes,
    );

    return ReadingPersonality(
      type: personalityType,
      timePreference: timePreference,
      sessionPattern: sessionPattern,
      consistencyScore: consistencyScore,
      avgSessionMinutes: avgSessionMinutes,
      currentStreak: streak.currentStreak,
      totalSessions: sessions.length,
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
      return SessionPattern.marathon; // Long sessions, fewer per day
    } else if (avgDuration < 20 && sessionsPerDay >= 2) {
      return SessionPattern.snacker; // Short sessions, many per day
    } else if (avgDuration >= 30 && avgDuration < 60) {
      return SessionPattern.balanced; // Medium sessions
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

    // Factors: streak length, regularity of sessions
    final streakScore = (streak / 30).clamp(0.0, 1.0) * 40; // Max 40 points for 30-day streak
    
    // Calculate how regular sessions are
    final uniqueDays = sessions.map((s) => s.dateString).toSet().length;
    final daysCovered = sessions.isNotEmpty
        ? DateTime.now().difference(sessions.last.startTime).inDays + 1
        : 1;
    final regularityScore = (uniqueDays / daysCovered.clamp(1, 30)) * 60; // Max 60 points

    return (streakScore + regularityScore).clamp(0, 100);
  }

  /// Determine personality type based on all factors
  PersonalityType _determinePersonalityType({
    required TimePreference timePreference,
    required SessionPattern sessionPattern,
    required double consistencyScore,
    required double avgSessionMinutes,
  }) {
    // High consistency = Dedicated
    if (consistencyScore >= 70) {
      return PersonalityType.dedicated;
    }
    
    // Marathon readers = Deep Diver
    if (sessionPattern == SessionPattern.marathon && avgSessionMinutes >= 60) {
      return PersonalityType.deepDiver;
    }
    
    // Night owls with consistent reading = Scholar
    if (timePreference == TimePreference.nightOwl && consistencyScore >= 50) {
      return PersonalityType.scholar;
    }
    
    // Snackers = Multitasker
    if (sessionPattern == SessionPattern.snacker) {
      return PersonalityType.multitasker;
    }
    
    // Early birds = Sunrise Reader
    if (timePreference == TimePreference.earlyBird) {
      return PersonalityType.sunriseReader;
    }
    
    // Default
    return PersonalityType.explorer;
  }
}

/// Reading personality profile
class ReadingPersonality {
  final PersonalityType type;
  final TimePreference timePreference;
  final SessionPattern sessionPattern;
  final double consistencyScore;
  final double avgSessionMinutes;
  final int currentStreak;
  final int totalSessions;

  const ReadingPersonality({
    required this.type,
    required this.timePreference,
    required this.sessionPattern,
    required this.consistencyScore,
    required this.avgSessionMinutes,
    required this.currentStreak,
    required this.totalSessions,
  });

  factory ReadingPersonality.empty() {
    return const ReadingPersonality(
      type: PersonalityType.explorer,
      timePreference: TimePreference.afternoonReader,
      sessionPattern: SessionPattern.casual,
      consistencyScore: 0,
      avgSessionMinutes: 0,
      currentStreak: 0,
      totalSessions: 0,
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
}

extension PersonalityTypeExt on PersonalityType {
  String get name {
    switch (this) {
      case PersonalityType.deepDiver:
        return 'Deep Diver';
      case PersonalityType.scholar:
        return 'Late Night Scholar';
      case PersonalityType.multitasker:
        return 'Multitasker';
      case PersonalityType.sunriseReader:
        return 'Sunrise Reader';
      case PersonalityType.dedicated:
        return 'Dedicated Listener';
      case PersonalityType.explorer:
        return 'Explorer';
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
        return 'Consistency is your superpower. You make time for reading every day without fail.';
      case PersonalityType.explorer:
        return 'You\'re just getting started! Keep reading to discover your unique listening style.';
    }
  }

  IconData get icon {
    switch (this) {
      case PersonalityType.deepDiver:
        return Icons.scuba_diving;
      case PersonalityType.scholar:
        return Icons.school;
      case PersonalityType.multitasker:
        return Icons.bolt;
      case PersonalityType.sunriseReader:
        return Icons.wb_sunny;
      case PersonalityType.dedicated:
        return Icons.star;
      case PersonalityType.explorer:
        return Icons.explore;
    }
  }

  Color get color {
    switch (this) {
      case PersonalityType.deepDiver:
        return const Color(0xFF1E88E5);
      case PersonalityType.scholar:
        return const Color(0xFF5E35B1);
      case PersonalityType.multitasker:
        return const Color(0xFFFF9800);
      case PersonalityType.sunriseReader:
        return const Color(0xFFFFB300);
      case PersonalityType.dedicated:
        return const Color(0xFF43A047);
      case PersonalityType.explorer:
        return const Color(0xFF00ACC1);
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
      case TimePreference.earlyBird:
        return 'Early Bird';
      case TimePreference.afternoonReader:
        return 'Afternoon Reader';
      case TimePreference.eveningEnthusiast:
        return 'Evening Enthusiast';
      case TimePreference.nightOwl:
        return 'Night Owl';
    }
  }

  IconData get icon {
    switch (this) {
      case TimePreference.earlyBird:
        return Icons.wb_sunny;
      case TimePreference.afternoonReader:
        return Icons.wb_twilight;
      case TimePreference.eveningEnthusiast:
        return Icons.nights_stay;
      case TimePreference.nightOwl:
        return Icons.dark_mode;
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
      case SessionPattern.marathon:
        return 'Marathon Sessions';
      case SessionPattern.snacker:
        return 'Quick Snacker';
      case SessionPattern.balanced:
        return 'Balanced';
      case SessionPattern.casual:
        return 'Casual';
    }
  }
}
