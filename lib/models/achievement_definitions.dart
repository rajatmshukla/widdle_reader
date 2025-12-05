import 'package:flutter/material.dart';
import '../models/achievement.dart';

/// Predefined achievement definitions
class AchievementDefinitions {
  static const Map<String, Achievement> all = {
    // =========================
    // TIME ACHIEVEMENTS
    // =========================
    'time_1h': Achievement(
      id: 'time_1h',
      name: 'Getting Started',
      description: 'Listen for 1 hour total',
      icon: Icons.timer,
      tier: AchievementTier.bronze,
      category: AchievementCategory.time,
      targetValue: 60, // minutes
    ),
    'time_10h': Achievement(
      id: 'time_10h',
      name: 'Dedicated Listener',
      description: 'Listen for 10 hours total',
      icon: Icons.timer,
      tier: AchievementTier.silver,
      category: AchievementCategory.time,
      targetValue: 600,
    ),
    'time_50h': Achievement(
      id: 'time_50h',
      name: 'Audiobook Enthusiast',
      description: 'Listen for 50 hours total',
      icon: Icons.timer,
      tier: AchievementTier.gold,
      category: AchievementCategory.time,
      targetValue: 3000,
    ),
    'time_100h': Achievement(
      id: 'time_100h',
      name: 'Century Club',
      description: 'Listen for 100 hours total',
      icon: Icons.timer,
      tier: AchievementTier.platinum,
      category: AchievementCategory.time,
      targetValue: 6000,
    ),
    'time_500h': Achievement(
      id: 'time_500h',
      name: 'Audio Master',
      description: 'Listen for 500 hours total',
      icon: Icons.emoji_events,
      tier: AchievementTier.diamond,
      category: AchievementCategory.time,
      targetValue: 30000,
    ),

    // =========================
    // STREAK ACHIEVEMENTS
    // =========================
    'streak_3': Achievement(
      id: 'streak_3',
      name: 'Getting Consistent',
      description: 'Maintain a 3-day reading streak',
      icon: Icons.local_fire_department,
      tier: AchievementTier.bronze,
      category: AchievementCategory.streak,
      targetValue: 3,
    ),
    'streak_7': Achievement(
      id: 'streak_7',
      name: 'Week Warrior',
      description: 'Maintain a 7-day reading streak',
      icon: Icons.local_fire_department,
      tier: AchievementTier.silver,
      category: AchievementCategory.streak,
      targetValue: 7,
    ),
    'streak_30': Achievement(
      id: 'streak_30',
      name: 'Monthly Master',
      description: 'Maintain a 30-day reading streak',
      icon: Icons.local_fire_department,
      tier: AchievementTier.gold,
      category: AchievementCategory.streak,
      targetValue: 30,
    ),
    'streak_100': Achievement(
      id: 'streak_100',
      name: 'Centurion',
      description: 'Maintain a 100-day reading streak',
      icon: Icons.whatshot,
      tier: AchievementTier.platinum,
      category: AchievementCategory.streak,
      targetValue: 100,
    ),
    'streak_365': Achievement(
      id: 'streak_365',
      name: 'Year of Reading',
      description: 'Maintain a 365-day reading streak',
      icon: Icons.auto_awesome,
      tier: AchievementTier.diamond,
      category: AchievementCategory.streak,
      targetValue: 365,
    ),

    // =========================
    // SESSION ACHIEVEMENTS
    // =========================
    'session_first': Achievement(
      id: 'session_first',
      name: 'First Steps',
      description: 'Complete your first reading session',
      icon: Icons.play_arrow,
      tier: AchievementTier.bronze,
      category: AchievementCategory.sessions,
      targetValue: 1,
    ),
    'session_10': Achievement(
      id: 'session_10',
      name: 'Regular Reader',
      description: 'Complete 10 reading sessions',
      icon: Icons.play_circle,
      tier: AchievementTier.silver,
      category: AchievementCategory.sessions,
      targetValue: 10,
    ),
    'session_50': Achievement(
      id: 'session_50',
      name: 'Session Veteran',
      description: 'Complete 50 reading sessions',
      icon: Icons.play_circle_filled,
      tier: AchievementTier.gold,
      category: AchievementCategory.sessions,
      targetValue: 50,
    ),
    'session_100': Achievement(
      id: 'session_100',
      name: 'Century Sessions',
      description: 'Complete 100 reading sessions',
      icon: Icons.verified,
      tier: AchievementTier.platinum,
      category: AchievementCategory.sessions,
      targetValue: 100,
    ),

    // =========================
    // SPECIAL ACHIEVEMENTS
    // =========================
    'night_owl': Achievement(
      id: 'night_owl',
      name: 'Night Owl',
      description: 'Read after midnight',
      icon: Icons.nightlight_round,
      tier: AchievementTier.bronze,
      category: AchievementCategory.special,
      isSecret: true,
    ),
    'early_bird': Achievement(
      id: 'early_bird',
      name: 'Early Bird',
      description: 'Read before 6 AM',
      icon: Icons.wb_sunny,
      tier: AchievementTier.bronze,
      category: AchievementCategory.special,
      isSecret: true,
    ),
    'weekend_warrior': Achievement(
      id: 'weekend_warrior',
      name: 'Weekend Warrior',
      description: 'Read 2+ hours on a weekend day',
      icon: Icons.weekend,
      tier: AchievementTier.silver,
      category: AchievementCategory.special,
      targetValue: 120, // 2 hours in minutes
    ),
    'marathon': Achievement(
      id: 'marathon',
      name: 'Marathon Reader',
      description: 'Read for 4+ hours in a single day',
      icon: Icons.directions_run,
      tier: AchievementTier.gold,
      category: AchievementCategory.special,
      targetValue: 240,
    ),
  };

  /// Get achievements by category
  static List<Achievement> getByCategory(AchievementCategory category) {
    return all.values.where((a) => a.category == category).toList();
  }

  /// Get achievements by tier
  static List<Achievement> getByTier(AchievementTier tier) {
    return all.values.where((a) => a.tier == tier).toList();
  }

  /// Get non-secret achievements
  static List<Achievement> getVisible() {
    return all.values.where((a) => !a.isSecret).toList();
  }

  /// Get total count
  static int get totalCount => all.length;
}
