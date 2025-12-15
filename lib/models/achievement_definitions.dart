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

    // =========================
    // BOOKS ACHIEVEMENTS
    // =========================
    'book_first': Achievement(
      id: 'book_first',
      name: 'First Finish',
      description: 'Complete your first audiobook',
      icon: Icons.menu_book,
      tier: AchievementTier.bronze,
      category: AchievementCategory.books,
      targetValue: 1,
    ),
    'book_5': Achievement(
      id: 'book_5',
      name: 'Bookshelf Builder',
      description: 'Complete 5 audiobooks',
      icon: Icons.menu_book,
      tier: AchievementTier.silver,
      category: AchievementCategory.books,
      targetValue: 5,
    ),
    'book_10': Achievement(
      id: 'book_10',
      name: 'Library Curator',
      description: 'Complete 10 audiobooks',
      icon: Icons.menu_book,
      tier: AchievementTier.gold,
      category: AchievementCategory.books,
      targetValue: 10,
    ),
    'book_25': Achievement(
      id: 'book_25',
      name: 'Avid Reader',
      description: 'Complete 25 audiobooks',
      icon: Icons.menu_book,
      tier: AchievementTier.platinum,
      category: AchievementCategory.books,
      targetValue: 25,
    ),

    // =========================
    // EXPLORER ACHIEVEMENTS
    // =========================
    'explore_genres': Achievement(
      id: 'explore_genres',
      name: 'Genre Explorer',
      description: 'Listen to 3 different books',
      icon: Icons.explore,
      tier: AchievementTier.bronze,
      category: AchievementCategory.explorer,
      targetValue: 3,
    ),
    'explore_long': Achievement(
      id: 'explore_long',
      name: 'Marathon Book',
      description: 'Finish a book longer than 10 hours',
      icon: Icons.explore,
      tier: AchievementTier.silver,
      category: AchievementCategory.explorer,
      targetValue: 1,
    ),

    // =========================
    // ENHANCED SESSION ACHIEVEMENTS
    // =========================
    'session_long_30': Achievement(
      id: 'session_long_30',
      name: 'Deep Diver',
      description: 'Complete a 30+ minute session',
      icon: Icons.timelapse,
      tier: AchievementTier.bronze,
      category: AchievementCategory.sessions,
      targetValue: 30,
    ),
    'session_long_60': Achievement(
      id: 'session_long_60',
      name: 'Hour of Power',
      description: 'Complete a 60+ minute session',
      icon: Icons.hourglass_full,
      tier: AchievementTier.silver,
      category: AchievementCategory.sessions,
      targetValue: 60,
    ),
    'session_200': Achievement(
      id: 'session_200',
      name: 'Session Legend',
      description: 'Complete 200 reading sessions',
      icon: Icons.verified,
      tier: AchievementTier.diamond,
      category: AchievementCategory.sessions,
      targetValue: 200,
    ),

    // =========================
    // LIBRARY ACHIEVEMENTS
    // =========================
    'library_10': Achievement(
      id: 'library_10',
      name: 'Growing Collection',
      description: 'Add 10 books to your library',
      icon: Icons.library_books,
      tier: AchievementTier.bronze,
      category: AchievementCategory.explorer,
      targetValue: 10,
    ),
    'library_25': Achievement(
      id: 'library_25',
      name: 'Book Hoarder',
      description: 'Add 25 books to your library',
      icon: Icons.library_books,
      tier: AchievementTier.silver,
      category: AchievementCategory.explorer,
      targetValue: 25,
    ),
    'library_50': Achievement(
      id: 'library_50',
      name: 'Master Collector',
      description: 'Add 50 books to your library',
      icon: Icons.library_books,
      tier: AchievementTier.gold,
      category: AchievementCategory.explorer,
      targetValue: 50,
    ),

    // =========================
    // BOOK COMPLETION MILESTONES
    // =========================
    'book_50': Achievement(
      id: 'book_50',
      name: 'Half Century',
      description: 'Complete 50 audiobooks',
      icon: Icons.emoji_events,
      tier: AchievementTier.diamond,
      category: AchievementCategory.books,
      targetValue: 50,
    ),

    // =========================
    // REVIEW ACHIEVEMENTS
    // =========================
    'review_first': Achievement(
      id: 'review_first',
      name: 'First Thoughts',
      description: 'Write your first book review',
      icon: Icons.rate_review,
      tier: AchievementTier.bronze,
      category: AchievementCategory.special,
      targetValue: 1,
    ),
    'review_5': Achievement(
      id: 'review_5',
      name: 'Thoughtful Reader',
      description: 'Write 5 book reviews',
      icon: Icons.rate_review,
      tier: AchievementTier.silver,
      category: AchievementCategory.special,
      targetValue: 5,
    ),
    'review_10': Achievement(
      id: 'review_10',
      name: 'Critic\'s Corner',
      description: 'Write 10 book reviews',
      icon: Icons.rate_review,
      tier: AchievementTier.gold,
      category: AchievementCategory.special,
      targetValue: 10,
    ),

    // =========================
    // TIME MILESTONES (Extended)
    // =========================
    'time_250h': Achievement(
      id: 'time_250h',
      name: 'Dedicated Scholar',
      description: 'Listen for 250 hours total',
      icon: Icons.school,
      tier: AchievementTier.platinum,
      category: AchievementCategory.time,
      targetValue: 15000, // 250 hours in minutes
    ),
    'time_1000h': Achievement(
      id: 'time_1000h',
      name: 'Audio Legend',
      description: 'Listen for 1000 hours total',
      icon: Icons.auto_awesome,
      tier: AchievementTier.diamond,
      category: AchievementCategory.time,
      targetValue: 60000, // 1000 hours in minutes
    ),

    // =========================
    // ADDITIONAL SPECIAL
    // =========================
    'speed_demon': Achievement(
      id: 'speed_demon',
      name: 'Speed Demon',
      description: 'Listen at 2x speed or faster',
      icon: Icons.speed,
      tier: AchievementTier.bronze,
      category: AchievementCategory.special,
      isSecret: true,
    ),
    'slow_and_steady': Achievement(
      id: 'slow_and_steady',
      name: 'Slow and Steady',
      description: 'Listen at 0.75x speed or slower',
      icon: Icons.slow_motion_video,
      tier: AchievementTier.bronze,
      category: AchievementCategory.special,
      isSecret: true,
    ),
    'favorite_fan': Achievement(
      id: 'favorite_fan',
      name: 'Favorite Fan',
      description: 'Add 5 books to favorites',
      icon: Icons.favorite,
      tier: AchievementTier.silver,
      category: AchievementCategory.special,
      targetValue: 5,
    ),
    'completionist': Achievement(
      id: 'completionist',
      name: 'Completionist',
      description: 'Complete all books in your library',
      icon: Icons.check_circle,
      tier: AchievementTier.diamond,
      category: AchievementCategory.special,
      isSecret: true,
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
