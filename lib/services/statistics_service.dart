import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:async';
import '../models/reading_session.dart';
import '../models/reading_statistics.dart';

/// Service for tracking and managing reading statistics
class StatisticsService {
  // Singleton pattern
  static final StatisticsService _instance = StatisticsService._internal();
  factory StatisticsService() => _instance;
  StatisticsService._internal();

  // SharedPreferences keys
  static const String sessionPrefix = 'reading_session_';
  static const String dailyStatsPrefix = 'daily_stats_';
  static const String streakDataKey = 'reading_streak';
  static const String activeSessionKey = 'active_session';
  static const String statsBackupSuffix = '_backup';

  // Cached instance
  SharedPreferences? _prefs;

  // Active session tracking
  ReadingSession? _activeSession;
  DateTime? _sessionStartTime;
  String? _currentAudiobookId;
  String? _currentChapterName;
  int _sessionPagesRead = 0;

  /// Initialize the service
  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ===========================
  // SESSION TRACKING
  // ===========================

  /// Start a new reading session
  Future<void> startSession({
    required String audiobookId,
    String? chapterName,
  }) async {
    try {
      // End any existing session first
      if (_activeSession != null) {
        await endSession();
      }

      _sessionStartTime = DateTime.now();
      _currentAudiobookId = audiobookId;
      _currentChapterName = chapterName;
      _sessionPagesRead = 0;

      debugPrint('📊 Started reading session for: $audiobookId');
    } catch (e) {
      debugPrint('Error starting session: $e');
    }
  }

  /// Update session progress (e.g., chapter changed)
  void updateSessionProgress({
    String? chapterName,
    bool incrementPages = false,
  }) {
    if (_sessionStartTime != null) {
      if (chapterName != null) {
        _currentChapterName = chapterName;
      }
      if (incrementPages) {
        _sessionPagesRead++;
      }
    }
  }

  /// End the current reading session
  Future<void> endSession() async {
    if (_sessionStartTime == null || _currentAudiobookId == null) {
      return; // No active session
    }

    try {
      final endTime = DateTime.now();
      final duration = endTime.difference(_sessionStartTime!).inMinutes;

      // Only save sessions longer than 1 minute
      if (duration >= 1) {
        final session = ReadingSession.fromTimes(
          audiobookId: _currentAudiobookId!,
          startTime: _sessionStartTime!,
          endTime: endTime,
          pagesRead: _sessionPagesRead,
          chapterName: _currentChapterName,
        );

        await _saveSession(session);
        await _updateDailyStats(session);
        await _updateStreak();

        debugPrint('📊 Ended reading session: ${session.durationMinutes} minutes');
      }

      // Clear active session
      _sessionStartTime = null;
      _currentAudiobookId = null;
      _currentChapterName = null;
      _sessionPagesRead = 0;
      _activeSession = null;
    } catch (e) {
      debugPrint('Error ending session: $e');
    }
  }

  /// Sync current session progress without ending it
  /// This allows for real-time stats updates
  Future<void> syncCurrentSession() async {
    if (_sessionStartTime == null || _currentAudiobookId == null) {
      return;
    }

    try {
      final now = DateTime.now();
      final duration = now.difference(_sessionStartTime!).inMinutes;

      // If session is > 1 min, we can consider saving a temporary snapshot
      // But for simplicity, we'll just update the streak and daily stats
      // by "ending" and "restarting" logically, OR we can just notify listeners if we had them.
      // A better approach for persistent stats is to save the accumulated time and reset start time.
      
      if (duration >= 1) {
        // Create a partial session
        final session = ReadingSession.fromTimes(
          audiobookId: _currentAudiobookId!,
          startTime: _sessionStartTime!,
          endTime: now,
          pagesRead: _sessionPagesRead,
          chapterName: _currentChapterName,
        );

        await _saveSession(session);
        await _updateDailyStats(session);
        await _updateStreak();

        // Reset start time to now to avoid double counting
        _sessionStartTime = now;
        _sessionPagesRead = 0; // Reset pages for next chunk
        
        debugPrint('📊 Synced reading session: ${session.durationMinutes} minutes');
      }
    } catch (e) {
      debugPrint('Error syncing session: $e');
    }
  }

  /// Save a session to storage
  Future<void> _saveSession(ReadingSession session) async {
    try {
      final prefs = await _preferences;
      final key = '$sessionPrefix${session.sessionId}';
      await prefs.setString(key, jsonEncode(session.toJson()));
    } catch (e) {
      debugPrint('Error saving session: $e');
    }
  }

  /// Update daily stats with new session
  Future<void> _updateDailyStats(ReadingSession session) async {
    try {
      final dateString = session.dateString;
      final currentStats = await getDailyStats(dateString);

      final updatedStats = DailyStats(
        date: dateString,
        totalMinutes: currentStats.totalMinutes + session.durationMinutes,
        sessionCount: currentStats.sessionCount + 1,
        pagesRead: currentStats.pagesRead + session.pagesRead,
        audiobooksRead: {
          ...currentStats.audiobooksRead,
          session.audiobookId,
        },
      );

      await _saveDailyStats(updatedStats);
    } catch (e) {
      debugPrint('Error updating daily stats: $e');
    }
  }

  /// Save daily stats
  Future<void> _saveDailyStats(DailyStats stats) async {
    try {
      final prefs = await _preferences;
      final key = '$dailyStatsPrefix${stats.date}';
      await prefs.setString(key, jsonEncode(stats.toJson()));
    } catch (e) {
      debugPrint('Error saving daily stats: $e');
    }
  }

  // ===========================
  // DATA QUERIES
  // ===========================

  /// Get daily stats for a specific date
  Future<DailyStats> getDailyStats(String date) async {
    try {
      final prefs = await _preferences;
      final key = '$dailyStatsPrefix$date';
      final jsonString = prefs.getString(key);

      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        return DailyStats.fromJson(json);
      }
    } catch (e) {
      debugPrint('Error loading daily stats for $date: $e');
    }

    return DailyStats.empty(date);
  }

  /// Get daily stats for a date range
  Future<Map<String, DailyStats>> getDailyStatsRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final stats = <String, DailyStats>{};

    try {
      var currentDate = DateTime(startDate.year, startDate.month, startDate.day);
      final end = DateTime(endDate.year, endDate.month, endDate.day);

      while (currentDate.isBefore(end) || currentDate.isAtSameMomentAs(end)) {
        final dateString =
            '${currentDate.year}-${currentDate.month.toString().padLeft(2, '0')}-${currentDate.day.toString().padLeft(2, '0')}';
        stats[dateString] = await getDailyStats(dateString);
        currentDate = currentDate.add(const Duration(days: 1));
      }
    } catch (e) {
      debugPrint('Error loading stats range: $e');
    }

    return stats;
  }

  /// Get all sessions for a specific date
  Future<List<ReadingSession>> getSessionsForDate(String date) async {
    final sessions = <ReadingSession>[];

    try {
      final prefs = await _preferences;
      final keys = prefs.getKeys().where((key) => key.startsWith(sessionPrefix));

      for (final key in keys) {
        final jsonString = prefs.getString(key);
        if (jsonString != null) {
          final session = ReadingSession.fromJson(
            jsonDecode(jsonString) as Map<String, dynamic>,
          );
          if (session.dateString == date) {
            sessions.add(session);
          }
        }
      }

      // Sort by start time
      sessions.sort((a, b) => a.startTime.compareTo(b.startTime));
    } catch (e) {
      debugPrint('Error loading sessions for $date: $e');
    }

    return sessions;
  }

  /// Get recent reading sessions (history log)
  Future<List<ReadingSession>> getRecentSessions(int limit) async {
    final sessions = <ReadingSession>[];

    try {
      final prefs = await _preferences;
      final keys = prefs.getKeys().where((key) => key.startsWith(sessionPrefix)).toList();

      for (final key in keys) {
        final jsonString = prefs.getString(key);
        if (jsonString != null) {
          sessions.add(ReadingSession.fromJson(
            jsonDecode(jsonString) as Map<String, dynamic>,
          ));
        }
      }

      // Sort by end time (newest first)
      sessions.sort((a, b) => b.endTime.compareTo(a.endTime));

      // Return limited number
      if (sessions.length > limit) {
        return sessions.sublist(0, limit);
      }
    } catch (e) {
      debugPrint('Error loading recent sessions: $e');
    }

    return sessions;
  }

  /// Get daily minutes for the current week (Mon-Sun)
  Future<List<int>> getWeeklyDailyMinutes() async {
    final now = DateTime.now();
    // Monday = 1, Sunday = 7
    final currentWeekday = now.weekday;
    final monday = now.subtract(Duration(days: currentWeekday - 1));
    
    final minutes = <int>[];
    
    for (int i = 0; i < 7; i++) {
      final day = monday.add(Duration(days: i));
      final dateString = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      final stats = await getDailyStats(dateString);
      minutes.add(stats.totalMinutes);
    }
    
    return minutes;
  }

  // ===========================
  // STREAKS
  // ===========================

  /// Update reading streak
  Future<void> _updateStreak() async {
    try {
      final streak = await getStreak();
      final today = DateTime.now();
      final todayString =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      // Calculate new streak
      int newCurrentStreak = 1;
      if (streak.lastReadDate != null) {
        final lastDate = DateTime(
          streak.lastReadDate!.year,
          streak.lastReadDate!.month,
          streak.lastReadDate!.day,
        );
        final todayDate = DateTime(today.year, today.month, today.day);
        final daysSinceLastRead = todayDate.difference(lastDate).inDays;

        if (daysSinceLastRead == 0) {
          // Same day, keep current streak
          newCurrentStreak = streak.currentStreak;
        } else if (daysSinceLastRead == 1) {
          // Consecutive day, increment streak
          newCurrentStreak = streak.currentStreak + 1;
        }
        // else: streak broken, reset to 1 (already set)
      }

      final newLongestStreak = newCurrentStreak > streak.longestStreak
          ? newCurrentStreak
          : streak.longestStreak;

      final updatedStreak = ReadingStreak(
        currentStreak: newCurrentStreak,
        longestStreak: newLongestStreak,
        lastReadDate: today,
      );

      await _saveStreak(updatedStreak);
    } catch (e) {
      debugPrint('Error updating streak: $e');
    }
  }

  /// Get current streak data
  Future<ReadingStreak> getStreak() async {
    try {
      final prefs = await _preferences;
      final jsonString = prefs.getString(streakDataKey);

      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        return ReadingStreak.fromJson(json);
      }
    } catch (e) {
      debugPrint('Error loading streak: $e');
    }

    return ReadingStreak.empty();
  }

  /// Save streak data
  Future<void> _saveStreak(ReadingStreak streak) async {
    try {
      final prefs = await _preferences;
      await prefs.setString(streakDataKey, jsonEncode(streak.toJson()));
    } catch (e) {
      debugPrint('Error saving streak: $e');
    }
  }

  // ===========================
  // INSIGHTS & ANALYTICS
  // ===========================

  /// Get average session duration
  Future<double> getAverageSessionDuration() async {
    try {
      final prefs = await _preferences;
      final keys = prefs.getKeys().where((key) => key.startsWith(sessionPrefix));

      if (keys.isEmpty) return 0.0;

      int totalMinutes = 0;
      int count = 0;

      for (final key in keys) {
        final jsonString = prefs.getString(key);
        if (jsonString != null) {
          final session = ReadingSession.fromJson(
            jsonDecode(jsonString) as Map<String, dynamic>,
          );
          totalMinutes += session.durationMinutes;
          count++;
        }
      }

      return count > 0 ? totalMinutes / count : 0.0;
    } catch (e) {
      debugPrint('Error calculating average session duration: $e');
      return 0.0;
    }
  }

  /// Get sessions per day average
  Future<double> getAverageSessionsPerDay() async {
    try {
      final prefs = await _preferences;
      final keys = prefs.getKeys().where((key) => key.startsWith(dailyStatsPrefix));

      if (keys.isEmpty) return 0.0;

      int totalSessions = 0;
      int daysWithSessions = 0;

      for (final key in keys) {
        final jsonString = prefs.getString(key);
        if (jsonString != null) {
          final stats = DailyStats.fromJson(
            jsonDecode(jsonString) as Map<String, dynamic>,
          );
          if (stats.sessionCount > 0) {
            totalSessions += stats.sessionCount;
            daysWithSessions++;
          }
        }
      }

      return daysWithSessions > 0 ? totalSessions / daysWithSessions : 0.0;
    } catch (e) {
      debugPrint('Error calculating average sessions per day: $e');
      return 0.0;
    }
  }

  /// Get total minutes for this week
  Future<int> getTotalMinutesThisWeek() async {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));

    return await _getTotalMinutesInRange(weekStart, weekEnd);
  }

  /// Get total minutes for this month
  Future<int> getTotalMinutesThisMonth() async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0);

    return await _getTotalMinutesInRange(monthStart, monthEnd);
  }

  /// Get total minutes in a date range
  Future<int> _getTotalMinutesInRange(DateTime start, DateTime end) async {
    try {
      final stats = await getDailyStatsRange(start, end);
      return stats.values.fold<int>(0, (sum, stat) => sum + stat.totalMinutes);
    } catch (e) {
      debugPrint('Error calculating total minutes: $e');
      return 0;
    }
  }

  /// Get total sessions for this week
  Future<int> getTotalSessionsThisWeek() async {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));

    return await _getTotalSessionsInRange(weekStart, weekEnd);
  }

  /// Get total sessions for this month
  Future<int> getTotalSessionsThisMonth() async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0);

    return await _getTotalSessionsInRange(monthStart, monthEnd);
  }

  /// Get total sessions in a date range
  Future<int> _getTotalSessionsInRange(DateTime start, DateTime end) async {
    try {
      final stats = await getDailyStatsRange(start, end);
      return stats.values.fold<int>(0, (sum, stat) => sum + stat.sessionCount);
    } catch (e) {
      debugPrint('Error calculating total sessions: $e');
      return 0;
    }
  }

  // ===========================
  // DATA MANAGEMENT
  // ===========================

  /// Reset all statistics (with backup)
  Future<void> resetAllStatistics() async {
    try {
      final prefs = await _preferences;

      // Create backup before reset
      await createBackup();

      // Find all statistics keys
      final keysToRemove = prefs.getKeys().where((key) =>
          key.startsWith(sessionPrefix) ||
          key.startsWith(dailyStatsPrefix) ||
          key == streakDataKey ||
          key == activeSessionKey);

      // Remove all statistics
      for (final key in keysToRemove) {
        await prefs.remove(key);
      }

      // Clear active session
      _sessionStartTime = null;
      _currentAudiobookId = null;
      _currentChapterName = null;
      _sessionPagesRead = 0;
      _activeSession = null;

      debugPrint('📊 All statistics reset successfully');
    } catch (e) {
      debugPrint('Error resetting statistics: $e');
      rethrow;
    }
  }

  /// Create backup of statistics
  Future<void> createBackup() async {
    try {
      final prefs = await _preferences;

      // Backup all session data
      for (final key in prefs.getKeys()) {
        if (key.startsWith(sessionPrefix) ||
            key.startsWith(dailyStatsPrefix) ||
            key == streakDataKey) {
          final value = prefs.getString(key);
          if (value != null) {
            await prefs.setString('$key$statsBackupSuffix', value);
          }
        }
      }

      debugPrint('📊 Statistics backup created');
    } catch (e) {
      debugPrint('Error creating statistics backup: $e');
    }
  }

  /// Restore from backup
  Future<bool> restoreFromBackup() async {
    try {
      final prefs = await _preferences;
      bool restoredAny = false;

      // Restore all backed up data
      for (final key in prefs.getKeys()) {
        if (key.endsWith(statsBackupSuffix)) {
          final originalKey = key.substring(0, key.length - statsBackupSuffix.length);
          final value = prefs.getString(key);
          if (value != null) {
            await prefs.setString(originalKey, value);
            restoredAny = true;
          }
        }
      }

      if (restoredAny) {
        debugPrint('📊 Statistics restored from backup');
      }

      return restoredAny;
    } catch (e) {
      debugPrint('Error restoring statistics: $e');
      return false;
    }
  }

  /// Get statistics data counts for health check
  Future<Map<String, int>> getDataCounts() async {
    try {
      final prefs = await _preferences;

      final sessionCount = prefs.getKeys()
          .where((key) => key.startsWith(sessionPrefix))
          .length;

      final dailyStatsCount = prefs.getKeys()
          .where((key) => key.startsWith(dailyStatsPrefix))
          .length;

      return {
        'sessions': sessionCount,
        'dailyStats': dailyStatsCount,
      };
    } catch (e) {
      debugPrint('Error getting statistics counts: $e');
      return {
        'sessions': 0,
        'dailyStats': 0,
      };
    }
  }
}
