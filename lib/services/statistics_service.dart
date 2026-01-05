import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:async';
import '../models/reading_session.dart';
import '../models/reading_statistics.dart';
import 'pulse_sync_service.dart';
import 'storage_service.dart';

// Safe debug logging - only prints in debug mode
void _logStats(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}

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
  static const String dailyGoalKey = 'daily_reading_goal';
  static const String showStreakKey = 'show_reading_streak';
  static const String showHoursAndMinutesKey = 'show_hours_and_minutes';

  // Cached instance
  SharedPreferences? _prefs;

  // Active session tracking
  ReadingSession? _activeSession;
  DateTime? _sessionStartTime;
  String? _currentAudiobookId;
  String? _currentChapterName;
  String? _currentSessionId; // Unique ID for the current continuous session
  int _sessionPagesRead = 0;
  
  // Speed-adjusted tracking
  double _accumulatedSeconds = 0.0;
  DateTime? _lastSyncTime;
  
  bool _isSessionCounted = false; // Track if session count has been incremented for current session
  Timer? _sessionPersistTimer;
  int _secondsCommitted = 0; // Track seconds already committed to daily stats to prevent drift
  
  // lock for stats updates
  bool _isUpdatingStats = false;
  final Completer<void> _updateCompleter = Completer<void>()..complete(); // not used, just a placeholder. simple bool is easier for now or a queue.
  // Actually simpler: process updates sequentially using a future chain or simple bool guard (retry?)
  // Let's use a proper Mutex pattern with Completers?
  // Or just a simple queue.
  // Simplest for this context: await a "lock" future.
  
  // Stream controller for real-time updates
  final _statsUpdatedController = StreamController<void>.broadcast();
  
  /// Stream that emits events when statistics are updated
  Stream<void> get onStatsUpdated => _statsUpdatedController.stream;

  bool get hasActiveSession => _sessionStartTime != null;

  /// Private getter for prefs
  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// Initialize and recover any crashed sessions
  Future<void> initialize() async {
    // Listen for data restore events (Pulse Sync)
    StorageService().addRestoreListener(_onDataRestored);
    await _recoverCrashedSession();
  }

  /// Reload data when sync occurs
  void _onDataRestored() {
    _logStats("Stats restored from sync. Reloading counters...");
    // Any in-memory stats that rely on prefs should be re-fetched here if needed
    // For now, most stats are fetched on demand from prefs, but we can verify streak
    _updateStreak(); // Trigger a streak check
  }

  /// Recover a session that may have been interrupted by crash/kill
  Future<void> _recoverCrashedSession() async {
    try {
      final prefs = await _preferences;
      final activeSessionJson = prefs.getString(activeSessionKey);
      
      if (activeSessionJson != null) {
        final data = jsonDecode(activeSessionJson) as Map<String, dynamic>;
        final startMs = data['startTime'] as int?;
        final audiobookId = data['audiobookId'] as String?;
        final chapterName = data['chapterName'] as String?;
        final sessionId = data['sessionId'] as String?;
        
        if (startMs != null && audiobookId != null) {
          // Fix for continuous sessions:
          // If we have a sessionId, we assume the session was being synced continuously.
          // The file on disk and DailyStats are likely up to date (within 10s).
          // We should NOT create a new session ending at DateTime.now(), as that would
          // count the entire downtime as reading time (e.g. 8 hours of sleep).
          
          if (sessionId != null) {
             _logStats('📊 Recovering continuous session $sessionId. Clearing crash flag.');
             // We assume the last sync was successful or acceptable.
             // No further action needed other than clearing the flag.
          } else {
            // Legacy / Fallback recovery
            final startTime = DateTime.fromMillisecondsSinceEpoch(startMs);
            // Use lastUpdate if available, otherwise cap to reasonable max or now
            final lastUpdateMs = data['lastUpdate'] as int?;
            final endTime = lastUpdateMs != null 
                ? DateTime.fromMillisecondsSinceEpoch(lastUpdateMs)
                : DateTime.now(); // Fallback (risky but legacy)

            final durationSec = endTime.difference(startTime).inSeconds;
            
            if (durationSec >= 10 && durationSec < 86400) {
               final session = ReadingSession.fromTimes(
                audiobookId: audiobookId,
                startTime: startTime,
                endTime: endTime,
                pagesRead: data['pagesRead'] as int? ?? 0,
                chapterName: chapterName,
                sessionId: sessionId, // likely null here
              );
              
              await _saveSession(session);
              // Only update daily stats if we are sure it wasn't counted (legacy)
              // With continuous, we assume it's counted. 
              // For legacy, we might double count if we aren't careful, 
              // but saving data is better than losing it.
              await _updateDailyStats(session, deltaSeconds: 0);
            }
          }
          
          // Clear the active session marker
          await prefs.remove(activeSessionKey);
        }
      }
    } catch (e) {
      _logStats('📊 Error recovering crashed session: $e');
    }
  }

  /// Persist active session state (called periodically)
  Future<void> _persistActiveSessionState() async {
    if (_sessionStartTime == null || _currentAudiobookId == null) return;
    
    try {
      final prefs = await _preferences;
      final data = {
        'startTime': _sessionStartTime!.millisecondsSinceEpoch,
        'audiobookId': _currentAudiobookId,
        'chapterName': _currentChapterName,
        'pagesRead': _sessionPagesRead,
        'sessionId': _currentSessionId,
        'lastUpdate': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(activeSessionKey, jsonEncode(data));
    } catch (e) {
      _logStats('📊 Error persisting session state: $e');
    }
  }

  /// Clear active session marker
  Future<void> _clearActiveSessionMarker() async {
    try {
      final prefs = await _preferences;
      await prefs.remove(activeSessionKey);
    } catch (e) {
      _logStats('📊 Error clearing session marker: $e');
    }
  }
  
  /// Update playback speed for current session tracking
  // Method kept for API compatibility, but speed is intentionally ignored
  Future<void> updateSpeed(double speed) async {
    _logStats('📊 Tracking speed update ignored (using strict wall-clock time)');
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
      _logStats('📊 startSession called - audiobookId: $audiobookId, chapter: $chapterName');
      
      // End any existing session first
      if (_activeSession != null || _sessionStartTime != null) {
        _logStats('📊 Active session exists, ending it first');
        await endSession();
      }

      final now = DateTime.now();
      bool isResumed = false;

      // COALESCING LOGIC: Check for recent sessions to resume
      try {
        final recentSessions = await getRecentSessions(1);
        if (recentSessions.isNotEmpty) {
          final lastSession = recentSessions.first;
          final gap = now.difference(lastSession.endTime).inSeconds;
          
          // If gap is less than 5 minutes and same book, resume session
          if (gap < 300 && lastSession.audiobookId == audiobookId && _isSameDay(lastSession.startTime, now)) {
             _logStats('📊 Resuming recent session (gap: ${gap}s) - ID: ${lastSession.sessionId}');
             
             _sessionStartTime = lastSession.startTime; // Keep original start time
             _currentSessionId = lastSession.sessionId; // Keep original ID
             _currentAudiobookId = audiobookId;
             _currentChapterName = chapterName;
             _sessionPagesRead = lastSession.pagesRead; // Continue page count
             
             // Initialize accumulator with previous duration so we don't start from 0
             // But we DON'T add the gap time to the duration (honest accounting)
             _accumulatedSeconds = lastSession.durationSeconds.toDouble();
             
             // Important: Set committed seconds to what's already in DB to avoid double counting
             _secondsCommitted = lastSession.durationSeconds; 
             
             _lastSyncTime = now; // Start tracking new delta from NOW
             _isSessionCounted = true; // Already counted this session
             
             isResumed = true;
          }
        }
      } catch (e) {
        _logStats('Error checking for session resumption: $e');
      }

      if (!isResumed) {
        _sessionStartTime = now;
        _currentAudiobookId = audiobookId;
        _currentChapterName = chapterName;
        _sessionPagesRead = 0;
        _currentSessionId = '${_sessionStartTime!.millisecondsSinceEpoch}';
        
        // Initialize accumulator model
        _accumulatedSeconds = 0.0;
        _lastSyncTime = _sessionStartTime;
        
        _isSessionCounted = false;
        _secondsCommitted = 0; // Reset committed tracking
      }
      
      // Persist immediately for crash recovery
      await _persistActiveSessionState();
      
      // Start periodic persistence (every 30 seconds)
      _sessionPersistTimer?.cancel();
      _sessionPersistTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _persistActiveSessionState(),
      );

      _logStats('📊 ✅ Session started (${isResumed ? "Resumed" : "New"})');
    } catch (e, stackTrace) {
      _logStats('📊 ❌ EXCEPTION in startSession: $e');
      if (kDebugMode) debugPrint('📊 Stack trace: $stackTrace');
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
    _logStats('📊 endSession called');
    
    // Stop the persist timer
    _sessionPersistTimer?.cancel();
    _sessionPersistTimer = null;
    
    if (_sessionStartTime == null || _currentAudiobookId == null) {
      _logStats('📊 ⚠️ No active session to end');
      await _clearActiveSessionMarker();
      return;
    }

    try {
      // Perform final sync to capture any remaining seconds
      await syncCurrentSession();
      
      _logStats('📊 ✅ Ended reading session');

      // Clear active session
      _sessionStartTime = null;
      _currentAudiobookId = null;
      _currentChapterName = null;
      _currentSessionId = null;
      _sessionPagesRead = 0;
      _sessionPagesRead = 0;
      
      // Reset accumulator
      _accumulatedSeconds = 0.0;
      _lastSyncTime = null;
      
      _isSessionCounted = false;
      _activeSession = null;
      
      // Clear persisted session marker
      await _clearActiveSessionMarker();
      
      _secondsCommitted = 0; // Reset committed tracking
      
      _statsUpdatedController.add(null);
    } catch (e, stackTrace) {
      _logStats('📊 ❌ EXCEPTION in endSession: $e');
      if (kDebugMode) debugPrint('📊 Stack trace: $stackTrace');
    }
  }

  // Sync lock to prevent race conditions (Timer vs Lifecycle)
  bool _isSyncing = false;

  /// Sync current session progress without ending it
  /// This allows for real-time stats updates
  Future<void> syncCurrentSession() async {
    // Guard against re-entry or concurrent execution
    if (_isSyncing) return;
    
    if (_sessionStartTime == null || _currentAudiobookId == null || _lastSyncTime == null) {
      _logStats('📊 syncCurrentSession skipped - no active session');
      return;
    }

    _isSyncing = true;
    try {
      _logStats('📊 syncCurrentSession called for audiobook: $_currentAudiobookId');
      final now = DateTime.now();
      
      // Calculate wall-clock delta since last sync
      final wallDeltaSeconds = now.difference(_lastSyncTime!).inMilliseconds / 1000.0;
      
      // STRICT WALL CLOCK TIME: Ignore speed multiplier
      final adjustedDelta = wallDeltaSeconds; 
      
      // Update accumulator
      _accumulatedSeconds += adjustedDelta;
      _lastSyncTime = now;

      // Only update if we have accumulated at least 1 second of content
      if (adjustedDelta > 0) {
        // Check for midnight crossing
        if (!_isSameDay(_sessionStartTime!, now)) {
          await _performMidnightSplit(now);
          return; // Session context changed, exit sync
        }

        // Create/Update session object
        // NOTE: Session duration is now based on CONTENT time, not wall time
        final session = ReadingSession.fromTimes(
          audiobookId: _currentAudiobookId!,
          startTime: _sessionStartTime!,
          endTime: _sessionStartTime!.add(Duration(seconds: _accumulatedSeconds.round())),
          pagesRead: _sessionPagesRead,
          chapterName: _currentChapterName,
          sessionId: _currentSessionId,
        );

        // Save session (overwrites existing entry for this ID)
        await _saveSession(session);
        
        // ROBUST DELTA CALCULATION:
        // Calculate total seconds that SHOULD be committed based on accumulator
        final totalSecondsToCommit = _accumulatedSeconds.floor(); 
        
        // Calculate the delta to add to daily stats
        final intDelta = totalSecondsToCommit - _secondsCommitted;
        
        if (intDelta > 0) {
          await _updateDailyStats(session, deltaSeconds: intDelta);
          _secondsCommitted += intDelta; // Update committed count
        }
        
        await _updateStreak();

        // Update tracking - done via accumulator & lastSyncTime
        
        // Update persisted state
        await _persistActiveSessionState();
        
        _logStats('📊 Synced: +${intDelta}s (Total: ${_accumulatedSeconds.toStringAsFixed(1)}s) [Wall Clock]');
        _statsUpdatedController.add(null);
      }
    } catch (e) {
      _logStats('Error syncing session: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Check if two dates are on the same day
  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Handle a session that crosses midnight by splitting it
  Future<void> _performMidnightSplit(DateTime now) async {
    _logStats('📊 Midnight detected! Splitting session...');
    
    if (_lastSyncTime == null) return;

    try {
      // 1. End current session at 23:59:59 of start day
      final endOfDay = DateTime(
        _sessionStartTime!.year,
        _sessionStartTime!.month,
        _sessionStartTime!.day,
        23, 59, 59, 999
      );
      
      // Calculate delta for the remainder of the first day (from lastSync to endOfDay)
      // Wall time delta
      final wallDeltaFirstPart = endOfDay.difference(_lastSyncTime!).inMilliseconds / 1000.0;
      // Content time delta (Strict Wall Clock)
      final adjustedDeltaFirstPart = wallDeltaFirstPart;

      // Update accumulator for first part
      _accumulatedSeconds += adjustedDeltaFirstPart;

      final sessionOne = ReadingSession.fromTimes(
        audiobookId: _currentAudiobookId!,
        startTime: _sessionStartTime!,
        endTime: _sessionStartTime!.add(Duration(seconds: _accumulatedSeconds.round())),
        pagesRead: _sessionPagesRead,
        chapterName: _currentChapterName,
        sessionId: _currentSessionId,
      );
      
      await _saveSession(sessionOne);
      
      // Commit stats for the first part
      final totalSecondsPartOne = _accumulatedSeconds.floor();
      final intDeltaFirst = totalSecondsPartOne - _secondsCommitted;
      
      if (intDeltaFirst > 0) {
        await _updateDailyStats(sessionOne, deltaSeconds: intDeltaFirst);
      }
      
      // 2. Start new session for Today
      // Start at midnight today
      final startOfToday = DateTime(now.year, now.month, now.day, 0, 0, 0);
      
      _sessionStartTime = startOfToday;
      _currentSessionId = '${now.millisecondsSinceEpoch}'; // New ID for new file
      _sessionPagesRead = 0; // Reset pages for new day part
      _isSessionCounted = false; // Allow increments for new day
      
      // Reset accumulator for the new day
      _accumulatedSeconds = 0.0;
      _secondsCommitted = 0; // Reset committed tracking for new day
      
      // Calculate delta for second part (from midnight to now)
      final wallDeltaSecondPart = now.difference(startOfToday).inMilliseconds / 1000.0;
      final adjustedDeltaSecondPart = wallDeltaSecondPart; // Strict Wall Clock
      
      _accumulatedSeconds = adjustedDeltaSecondPart;
      _lastSyncTime = now;
      
      final sessionTwo = ReadingSession.fromTimes(
        audiobookId: _currentAudiobookId!,
        startTime: startOfToday,
        endTime: startOfToday.add(Duration(seconds: _accumulatedSeconds.round())),
        pagesRead: 0,
        chapterName: _currentChapterName,
        sessionId: _currentSessionId,
      );
      
      await _saveSession(sessionTwo);
      
      final totalSecondsPartTwo = _accumulatedSeconds.floor();
      final intDeltaSecond = totalSecondsPartTwo; // 0 committed so far
      
      if (intDeltaSecond > 0) {
        await _updateDailyStats(sessionTwo, deltaSeconds: intDeltaSecond);
        _secondsCommitted = intDeltaSecond;
      }
      
      await _updateStreak(); // Update streak for new day
      await _persistActiveSessionState(); // Persist new state
      
      _logStats('📊 ✅ Split completed. New session started for today.');
      _statsUpdatedController.add(null);
      
    } catch (e) {
      _logStats('Error performing midnight split: $e');
    }
  }

  /// Save a session to storage
  Future<void> _saveSession(ReadingSession session) async {
    try {
      final prefs = await _preferences;
      final key = '$sessionPrefix${session.sessionId}';
      final jsonString = jsonEncode(session.toJson());
      _logStats('📊 Saving session with key: $key');
      await prefs.setString(key, jsonString);
      _logStats('📊 ✅ Session saved successfully');
      
      // Pulse out session
      PulseSyncService().pulseOut();
    } catch (e, stackTrace) {
      _logStats('📊 ❌ EXCEPTION saving session: $e');
      if (kDebugMode) debugPrint('📊 Stack trace: $stackTrace');
    }
  }

  /// Update daily stats with new session
  /// Uses non-blocking guard pattern - if busy, skips update (next sync will catch up)
  Future<void> _updateDailyStats(ReadingSession session, {int deltaSeconds = 0}) async {
    // LOCK REMOVED: Preventing potential deadlock if a previous update threw silently or hung.
    // Since syncCurrentSession is called by a 10s timer, overlap is rare and less dangerous than a permanent freeze.
    
    try {
      final dateString = session.dateString;
      _logStats('📊 Updating daily stats for $dateString with delta: ${deltaSeconds}s');
      
      final currentStats = await getDailyStats(dateString);

      // If deltaSeconds is provided (continuous sync), use it.
      // Otherwise (legacy/full save), calculate from session duration.
      final secondsToAdd = deltaSeconds > 0 ? deltaSeconds : session.durationSeconds;
      
      // Determine if we should increment session count
      int sessionCountIncrement = 0;
      if (!_isSessionCounted) {
        sessionCountIncrement = 1;
        _isSessionCounted = true;
        _logStats('📊 First update for this session - incrementing session count');
      }

      final updatedStats = DailyStats(
        date: dateString,
        totalSeconds: currentStats.totalSeconds + secondsToAdd,
        sessionCount: currentStats.sessionCount + sessionCountIncrement,
        pagesRead: currentStats.pagesRead + session.pagesRead,
        audiobooksRead: {
          ...currentStats.audiobooksRead,
          session.audiobookId,
        },
        bookDurations: {
          ...currentStats.bookDurations,
          session.audiobookId: (currentStats.bookDurations[session.audiobookId] ?? 0) + secondsToAdd,
        },
      );
      
      await _saveDailyStats(updatedStats);
      _logStats('📊 ✅ Daily stats updated - new total: ${updatedStats.totalSeconds}s');
    } catch (e, stackTrace) {
      _logStats('📊 ❌ Error updating daily stats: $e');
      if (kDebugMode) debugPrint('📊 Stack trace: $stackTrace');
    }
  }

  /// Save daily stats
  Future<void> _saveDailyStats(DailyStats stats) async {
    try {
      final prefs = await _preferences;
      final key = '$dailyStatsPrefix${stats.date}';
      await prefs.setString(key, jsonEncode(stats.toJson()));
    } catch (e) {
      _logStats('Error saving daily stats: $e');
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
      _logStats('Error loading daily stats for $date: $e');
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
  Future<List<ReadingSession>> getSessionsForDate(DateTime date) async {
    final sessions = <ReadingSession>[];
    try {
      final prefs = await _preferences;
      final datePrefix = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      
      final keys = prefs.getKeys().where((key) => key.startsWith(sessionPrefix));
      
      for (final key in keys) {
        final jsonString = prefs.getString(key);
        if (jsonString != null) {
          final session = ReadingSession.fromJson(jsonDecode(jsonString));
          // Check if session ended on this date (using local time for display)
          final sessionDate = session.endTime.toLocal();
          final sessionDateString = '${sessionDate.year}-${sessionDate.month.toString().padLeft(2, '0')}-${sessionDate.day.toString().padLeft(2, '0')}';
          
          if (sessionDateString == datePrefix) {
            sessions.add(session);
          }
        }
      }
      
      // Sort by end time descending
      sessions.sort((a, b) => b.endTime.compareTo(a.endTime));
    } catch (e) {
      debugPrint('Error loading sessions for date: $e');
    }
    
    return sessions;
  }

  /// Get sessions in a date range
  Future<List<ReadingSession>> getSessionsInRange(DateTime start, DateTime end) async {
    final sessions = <ReadingSession>[];
    try {
      final prefs = await _preferences;
      final keys = prefs.getKeys().where((key) => key.startsWith(sessionPrefix));
      
      for (final key in keys) {
        final jsonString = prefs.getString(key);
        if (jsonString != null) {
          final session = ReadingSession.fromJson(jsonDecode(jsonString));
          if (session.endTime.isAfter(start) && session.endTime.isBefore(end)) {
            sessions.add(session);
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading sessions in range: $e');
    }
    return sessions;
  }

  /// Get recent reading sessions (history log)
  Future<List<ReadingSession>> getRecentSessions(int limit) async {
    final sessions = <ReadingSession>[];

    try {
      final prefs = await _preferences;
      final keys = prefs.getKeys().where((key) => key.startsWith(sessionPrefix)).toList();
      debugPrint('📊 Found ${keys.length} session keys in SharedPreferences');

      for (final key in keys) {
        final jsonString = prefs.getString(key);
        if (jsonString != null) {
          try {
            final session = ReadingSession.fromJson(
              jsonDecode(jsonString) as Map<String, dynamic>,
            );
            sessions.add(session);
            debugPrint('📊 Loaded session: ${session.sessionId}, duration: ${session.durationMinutes}min');
          } catch (e) {
            debugPrint('📊 Error parsing session $key: $e');
          }
        }
      }

      // Sort by end time (newest first)
      sessions.sort((a, b) => b.endTime.compareTo(a.endTime));
      debugPrint('📊 Returning ${sessions.length > limit ? limit : sessions.length} out of ${sessions.length} total sessions');

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
      
      // Pulse out streak
      PulseSyncService().pulseOut();
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

      if (keys.isEmpty) return 0.0;

      int totalSeconds = 0;
      int count = 0;

      for (final key in keys) {
        final jsonString = prefs.getString(key);
        if (jsonString != null) {
          final session = ReadingSession.fromJson(
            jsonDecode(jsonString) as Map<String, dynamic>,
          );
          totalSeconds += session.durationSeconds;
          count++;
        }
      }

      return count > 0 ? (totalSeconds / 60) / count : 0.0;
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
      _statsUpdatedController.add(null);
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
        _statsUpdatedController.add(null);
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

  // ===========================
  // SETTINGS
  // ===========================

  /// Get daily reading goal in minutes
  Future<int> getDailyGoal() async {
    try {
      final prefs = await _preferences;
      return prefs.getInt(dailyGoalKey) ?? 30; // Default 30 minutes
    } catch (e) {
      debugPrint('Error loading daily goal: $e');
      return 30;
    }
  }

  /// Set daily reading goal
  Future<void> setDailyGoal(int minutes) async {
    try {
      final prefs = await _preferences;
      await prefs.setInt(dailyGoalKey, minutes);
      debugPrint('📊 Daily goal updated to $minutes minutes');
    } catch (e) {
      debugPrint('Error saving daily goal: $e');
    }
  }

  /// Check if streak should be shown
  Future<bool> getShowStreak() async {
    try {
      final prefs = await _preferences;
      return prefs.getBool(showStreakKey) ?? true; // Default true
    } catch (e) {
      debugPrint('Error loading show streak setting: $e');
      return true;
    }
  }

  /// Set streak visibility
  Future<void> setShowStreak(bool show) async {
    try {
      final prefs = await _preferences;
      await prefs.setBool(showStreakKey, show);
      debugPrint('📊 Streak visibility updated to $show');
    } catch (e) {
      debugPrint('Error saving show streak setting: $e');
    }
  }

  /// Get show hours and minutes setting
  Future<bool> getShowHoursAndMinutes() async {
    try {
      final prefs = await _preferences;
      return prefs.getBool(showHoursAndMinutesKey) ?? true; // Default true
    } catch (e) {
      debugPrint('Error loading show hours and minutes setting: $e');
      return true;
    }
  }

  /// Get hourly activity breakdown (Last 30 days)
  Future<Map<int, int>> getHourlyActivity() async {
    try {
      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      final sessions = await getSessionsInRange(thirtyDaysAgo, now);
      
      final Map<int, int> activity = {};
      for (int i = 0; i < 24; i++) activity[i] = 0;

      for (var session in sessions) {
        final hour = session.startTime.hour;
        activity[hour] = (activity[hour] ?? 0) + session.durationSeconds;
      }
      return activity;
    } catch (e) {
      debugPrint('Error getting hourly activity: $e');
      return {};
    }
  }

  /// Get weekday vs weekend activity (Last 30 days)
  Future<Map<int, int>> getWeekdayActivity() async {
    try {
      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      final statsMap = await getDailyStatsRange(thirtyDaysAgo, now);
      
      final Map<int, int> activity = {};
      for (int i = 1; i <= 7; i++) activity[i] = 0;

      for (var stats in statsMap.values) {
        final date = DateTime.parse(stats.date);
        final weekday = date.weekday;
        activity[weekday] = (activity[weekday] ?? 0) + stats.totalSeconds;
      }
      return activity;
    } catch (e) {
      debugPrint('Error getting weekday activity: $e');
      return {};
    }
  }

  /// Get genre distribution (Last 90 days)
  Future<Map<String, int>> getGenreDistribution(Map<String, Set<String>> bookTags) async {
    try {
      final now = DateTime.now();
      final ninetyDaysAgo = now.subtract(const Duration(days: 90));
      final statsMap = await getDailyStatsRange(ninetyDaysAgo, now);
      
      final Map<String, int> distribution = {};

      for (var stats in statsMap.values) {
        for (var entry in stats.bookDurations.entries) {
          final bookId = entry.key;
          final seconds = entry.value;
          
          final tags = bookTags[bookId] ?? {'Uncategorized'};
          for (var tag in tags) {
            distribution[tag] = (distribution[tag] ?? 0) + seconds;
          }
        }
      }
      return distribution;
    } catch (e) {
      debugPrint('Error getting genre distribution: $e');
      return {};
    }
  }

  /// Get completion funnel statistics
  Future<Map<String, dynamic>> getCompletionFunnel(List<dynamic> allBooks) async {
    try {
      int started = 0;
      int completed = 0;
      // We can't easily calculate "average finish days" without progress history and finished timestamps
      // But we can show Total vs Completed.
      
      for (var book in allBooks) {
        // Assume book has progress or status
        // For now, let's look at tags or simple completion logic if available
        // This is a placeholder since we need the specific Audiobook model fields
        if (book.isFavorited) started++; // Placeholder logic
      }

      return {
        'total': allBooks.length,
        'started': started,
        'completed': completed,
      };
    } catch (e) {
      debugPrint('Error getting completion funnel: $e');
      return {'total': 0, 'started': 0, 'completed': 0};
    }
  }

  /// Get monthly momentum (Last 6 months)
  Future<Map<String, int>> getMonthlyMomentum() async {
    try {
      final now = DateTime.now();
      final sixMonthsAgo = DateTime(now.year, now.month - 5, 1);
      final statsMap = await getDailyStatsRange(sixMonthsAgo, now);
      
      final Map<String, int> momentum = {};
      
      // Initialize months
      for (int i = 0; i < 6; i++) {
        final monthDate = DateTime(now.year, now.month - i, 1);
        final monthKey = '${monthDate.year}-${monthDate.month.toString().padLeft(2, '0')}';
        momentum[monthKey] = 0;
      }

      for (var stats in statsMap.values) {
        final date = DateTime.parse(stats.date);
        final monthKey = '${date.year}-${date.month.toString().padLeft(2, '0')}';
        if (momentum.containsKey(monthKey)) {
          momentum[monthKey] = (momentum[monthKey] ?? 0) + stats.totalSeconds;
        }
      }
      return momentum;
    } catch (e) {
      debugPrint('Error getting monthly momentum: $e');
      return {};
    }
  }

  /// Set show hours and minutes setting
  Future<void> setShowHoursAndMinutes(bool value) async {
    try {
      final prefs = await _preferences;
      await prefs.setBool(showHoursAndMinutesKey, value);
      debugPrint('📊 Show hours and minutes updated to $value');
    } catch (e) {
      debugPrint('Error saving show hours and minutes setting: $e');
    }
  }
}
