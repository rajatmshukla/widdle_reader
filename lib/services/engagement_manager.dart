import 'package:flutter/material.dart';
import '../services/personality_service.dart';
import '../services/notification_service.dart';
import '../services/statistics_service.dart';
import 'dart:math';

class EngagementManager {
  static final EngagementManager _instance = EngagementManager._internal();
  factory EngagementManager({
    NotificationService? notificationService,
    StatisticsService? statsService,
    PersonalityService? personalityService,
  }) {
    if (notificationService != null) {
      _instance._notificationService = notificationService;
    }
    if (statsService != null) {
      _instance._statsService = statsService;
    }
    if (personalityService != null) {
      _instance._personalityService = personalityService;
    }
    return _instance;
  }

  EngagementManager._internal();

  NotificationService _notificationService = NotificationService();
  StatisticsService _statsService = StatisticsService();
  PersonalityService _personalityService = PersonalityService();

  Future<void> initialize() async {
    // Schedule engagement checks on app startup
    await _scheduleNextReminder();
  }

  /// Record a listening session and update engagement state
  Future<void> recordListeningSession() async {
    // The statistics service handles session tracking
    // We just need to refresh the notification schedule
    await _scheduleNextReminder();
  }

  /// Get current streak from statistics service
  Future<int> getStreak() async {
    final streak = await _statsService.getStreak();
    return streak.currentStreak;
  }

  /// Schedule the next engagement reminder
  Future<void> _scheduleNextReminder() async {
    try {
      // 1. Get Personality & Streak
      final personality = await _personalityService.analyzePersonality();
      final streak = await _statsService.getStreak();

      // 2. Determine base time
      DateTime scheduledTime = _calculatePreferredTime(personality.timePreference);

      // 3. Apply Quiet Hours (10 PM - 8 AM)
      scheduledTime = _applyQuietHours(scheduledTime);

      // 4. Determine content type (Streak vs General)
      String title;
      String body;

      // If user has a streak > 1 and hasn't read today, prioritize streak reminder
      // But if they HAVE read today, schedule for tomorrow
      final hasReadToday = streak.lastReadDate != null && 
          _isSameDay(streak.lastReadDate!, DateTime.now());

      if (hasReadToday) {
        // Schedule for tomorrow
        scheduledTime = scheduledTime.add(const Duration(days: 1));
      } else if (scheduledTime.isBefore(DateTime.now())) {
          // If preferred time passed for today, schedule for tomorrow
          scheduledTime = scheduledTime.add(const Duration(days: 1));
      }

      if (streak.currentStreak > 1) {
        title = "🔥 Keep the Streak Alive!";
        body = _getStreakMessage(streak.currentStreak);
      } else {
        title = "📖 Time to Read?";
        body = _getEngagementMessage(personality);
      }

      // 5. Schedule RECURRING notification (fires daily at this time)
      // Use a fixed ID (100) to ensure only one recurring reminder is active
      await _notificationService.scheduleDailyRecurringNotification(
        id: 100,
        title: title,
        body: body,
        hour: scheduledTime.hour,
        minute: scheduledTime.minute,
      );
      
      debugPrint('📅 Engagement reminder scheduled for ${scheduledTime.hour}:${scheduledTime.minute}');
    } catch (e) {
      debugPrint('Error scheduling engagement reminder: $e');
    }
  }

  /// Calculate preferred time based on personality
  DateTime _calculatePreferredTime(TimePreference preference) {
    final now = DateTime.now();
    int hour = 18; // Default evening

    switch (preference) {
      case TimePreference.earlyBird:
        hour = 7;
        break;
      case TimePreference.afternoonReader:
        hour = 13;
        break;
      case TimePreference.eveningEnthusiast:
        hour = 19;
        break;
      case TimePreference.nightOwl:
        hour = 21; // 9 PM set as max "preferred" time to avoid conflict, but we double check
        break;
    }

    return DateTime(now.year, now.month, now.day, hour, 0);
  }

  /// Ensure time is outside 10 PM - 8 AM
  DateTime _applyQuietHours(DateTime input) {
    // Quiet hours: 22:00 (10 PM) to 08:00 (8 AM)
    // If time is >= 22:00, move to next day 9:00 AM
    // If time is < 08:00, move to 09:00 AM same day (or next day depending on context)

    if (input.hour >= 22) {
      // Move to next morning 9 AM
      return DateTime(input.year, input.month, input.day + 1, 9, 0);
    } else if (input.hour < 8) {
      // Move to 9 AM same day
      return DateTime(input.year, input.month, input.day, 9, 0);
    }

    return input;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Fun streak messages
  String _getStreakMessage(int streakDays) {
    final messages = [
      "🔥 Day $streakDays! Keep the fire burning!",
      "📚 $streakDays days in a row? You're a reading machine!",
      "🚀 Day $streakDays! To infinity and beyond!",
      "Don't break the chain! Day $streakDays awaits.",
      "You're unstoppable! Day $streakDays is here.",
      "Consistency is key! Day $streakDays.",
    ];
    return messages[Random().nextInt(messages.length)];
  }

  /// Personalized engagement messages
  String _getEngagementMessage(ReadingPersonality personality) {
    // Default messages
    final defaults = [
      "Your library misses you! 📚",
      "Ready for another chapter?",
      "Escape into a good book today.",
    ];

    // Personality specific
    if (personality.type == PersonalityType.deepDiver) {
      return "Ready to dive deep again? 🌊";
    } else if (personality.type == PersonalityType.scholar) {
      return "The night is young for reading! 🦉";
    } else if (personality.type == PersonalityType.sunriseReader) {
      return "Start your day with a story! ☀️";
    }

    return defaults[Random().nextInt(defaults.length)];
  }
}
