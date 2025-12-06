import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:async';
import '../models/achievement.dart';
import '../models/achievement_definitions.dart';
import 'statistics_service.dart';

/// Service for managing achievements and badge unlocking
class AchievementService {
  // Singleton pattern
  static final AchievementService _instance = AchievementService._internal();
  factory AchievementService() => _instance;
  AchievementService._internal();

  // SharedPreferences keys
  static const String unlockedAchievementsKey = 'unlocked_achievements';
  static const String lastCheckTimestampKey = 'achievement_last_check';

  // Cached instance
  SharedPreferences? _prefs;
  final StatisticsService _statsService = StatisticsService();

  // Unlocked achievements cache
  final Map<String, Achievement> _unlockedAchievements = {};
  bool _initialized = false;

  // Stream controller for new unlocks
  final StreamController<Achievement> _unlockController =
      StreamController<Achievement>.broadcast();
  Stream<Achievement> get unlockStream => _unlockController.stream;

  /// Initialize the service
  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// Initialize and load unlocked achievements
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final prefs = await _preferences;
      final jsonString = prefs.getString(unlockedAchievementsKey);

      if (jsonString != null) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        for (final json in jsonList) {
          final achievement = Achievement.fromStoredData(
            json as Map<String, dynamic>,
            AchievementDefinitions.all,
          );
          if (achievement != null) {
            _unlockedAchievements[achievement.id] = achievement;
          }
        }
      }

      // Listen to statistics updates to trigger achievement checks
      _statsService.onStatsUpdated.listen((_) {
        checkAndUnlockAchievements();
      });

      _initialized = true;
      debugPrint('🏆 AchievementService initialized with ${_unlockedAchievements.length} unlocked achievements');
      
      // Initial check
      checkAndUnlockAchievements();
    } catch (e) {
      debugPrint('Error initializing AchievementService: $e');
    }
  }

  /// Check for new achievements and unlock them
  Future<List<Achievement>> checkAndUnlockAchievements() async {
    await initialize();
    final newUnlocks = <Achievement>[];

    try {
      // Get current stats
      final streak = await _statsService.getStreak();
      final recentSessions = await _statsService.getRecentSessions(1000);
      final totalMinutes = recentSessions.fold<int>(
        0,
        (sum, s) => sum + s.durationMinutes,
      );
      final sessionCount = recentSessions.length;

      // Get today's stats
      final now = DateTime.now();
      final todayString =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final todayStats = await _statsService.getDailyStats(todayString);

      // Check each achievement
      for (final definition in AchievementDefinitions.all.values) {
        if (_unlockedAchievements.containsKey(definition.id)) {
          continue; // Already unlocked
        }

        final shouldUnlock = _checkAchievementCriteria(
          definition,
          totalMinutes: totalMinutes,
          currentStreak: streak.currentStreak,
          longestStreak: streak.longestStreak,
          sessionCount: sessionCount,
          todayMinutes: todayStats.totalMinutes,
          currentHour: now.hour,
          isWeekend: now.weekday == 6 || now.weekday == 7,
        );

        if (shouldUnlock) {
          final unlockedAchievement = definition.unlock();
          _unlockedAchievements[definition.id] = unlockedAchievement;
          newUnlocks.add(unlockedAchievement);
          _unlockController.add(unlockedAchievement);
          debugPrint('🏆 Achievement unlocked: ${definition.name}');
        }
      }

      // Save if any new unlocks
      if (newUnlocks.isNotEmpty) {
        await _saveUnlockedAchievements();
      }
    } catch (e) {
      debugPrint('Error checking achievements: $e');
    }

    return newUnlocks;
  }

  /// Check if a specific achievement should be unlocked
  bool _checkAchievementCriteria(
    Achievement achievement, {
    required int totalMinutes,
    required int currentStreak,
    required int longestStreak,
    required int sessionCount,
    required int todayMinutes,
    required int currentHour,
    required bool isWeekend,
  }) {
    final target = achievement.targetValue ?? 0;

    switch (achievement.category) {
      case AchievementCategory.time:
        return totalMinutes >= target;

      case AchievementCategory.streak:
        return longestStreak >= target;

      case AchievementCategory.sessions:
        return sessionCount >= target;

      case AchievementCategory.special:
        return _checkSpecialAchievement(
          achievement.id,
          totalMinutes: totalMinutes,
          todayMinutes: todayMinutes,
          currentHour: currentHour,
          isWeekend: isWeekend,
        );

      default:
        return false;
    }
  }

  /// Check special achievement criteria
  bool _checkSpecialAchievement(
    String id, {
    required int totalMinutes,
    required int todayMinutes,
    required int currentHour,
    required bool isWeekend,
  }) {
    switch (id) {
      case 'night_owl':
        return currentHour >= 0 && currentHour < 5;
      case 'early_bird':
        return currentHour >= 4 && currentHour < 6;
      case 'weekend_warrior':
        return isWeekend && todayMinutes >= 120;
      case 'marathon':
        return todayMinutes >= 240;
      default:
        return false;
    }
  }

  /// Save unlocked achievements to storage
  Future<void> _saveUnlockedAchievements() async {
    try {
      final prefs = await _preferences;
      final jsonList = _unlockedAchievements.values
          .map((a) => a.toJson())
          .toList();
      await prefs.setString(unlockedAchievementsKey, jsonEncode(jsonList));
      await prefs.setInt(lastCheckTimestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('Error saving achievements: $e');
    }
  }

  /// Get all achievements with unlock status
  Future<List<Achievement>> getAllAchievements() async {
    await initialize();

    return AchievementDefinitions.all.values.map((definition) {
      final unlocked = _unlockedAchievements[definition.id];
      return unlocked ?? definition;
    }).toList();
  }

  /// Get unlocked achievements only
  List<Achievement> getUnlockedAchievements() {
    return _unlockedAchievements.values.toList();
  }

  /// Get unlock progress for a specific achievement
  Future<double> getProgress(String achievementId) async {
    final definition = AchievementDefinitions.all[achievementId];
    if (definition == null || definition.targetValue == null) {
      return 0.0;
    }

    final target = definition.targetValue!;
    int current = 0;

    switch (definition.category) {
      case AchievementCategory.time:
        final sessions = await _statsService.getRecentSessions(1000);
        current = sessions.fold<int>(0, (sum, s) => sum + s.durationMinutes);
        break;
      case AchievementCategory.streak:
        final streak = await _statsService.getStreak();
        current = streak.longestStreak;
        break;
      case AchievementCategory.sessions:
        final sessions = await _statsService.getRecentSessions(1000);
        current = sessions.length;
        break;
      default:
        return 0.0;
    }

    return (current / target).clamp(0.0, 1.0);
  }

  /// Get count of unlocked achievements
  int get unlockedCount => _unlockedAchievements.length;

  /// Get total achievement count
  int get totalCount => AchievementDefinitions.totalCount;

  /// Get achievements by category
  Future<Map<AchievementCategory, List<Achievement>>> getAchievementsByCategory() async {
    final all = await getAllAchievements();
    final byCategory = <AchievementCategory, List<Achievement>>{};

    for (final category in AchievementCategory.values) {
      byCategory[category] = all.where((a) => a.category == category).toList();
    }

    return byCategory;
  }

  /// Reset all achievements (for testing)
  Future<void> resetAllAchievements() async {
    try {
      final prefs = await _preferences;
      await prefs.remove(unlockedAchievementsKey);
      await prefs.remove(lastCheckTimestampKey);
      _unlockedAchievements.clear();
      debugPrint('🏆 All achievements reset');
    } catch (e) {
      debugPrint('Error resetting achievements: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _unlockController.close();
  }
}
