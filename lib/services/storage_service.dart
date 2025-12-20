import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:convert'; // Add this import for JSON encoding/decoding
import 'dart:typed_data'; // For Uint8List
import 'package:path_provider/path_provider.dart';
import '../models/bookmark.dart'; // Import the Bookmark model
import 'dart:async'; // For periodic cache persistence
import '../models/audiobook.dart'; // Import Audiobook model

class StorageService {
  // Listeners for data restore events
  final List<VoidCallback> _restoreListeners = [];

  void addRestoreListener(VoidCallback listener) {
    _restoreListeners.add(listener);
  }

  void removeRestoreListener(VoidCallback listener) {
    _restoreListeners.remove(listener);
  }

  void _notifyRestoreListeners() {
    for (final listener in _restoreListeners) {
      try {
        listener();
      } catch (e) {
        debugPrint('Error in restore listener: $e');
      }
    }
  }
  // Key constants for SharedPreferences
  static const String foldersKey = 'audiobook_folders';

  static const lastPositionPrefix = 'last_pos_';
  static const customTitlesKey = 'custom_titles';
  static const progressCachePrefix = 'progress_cache_';
  static const lastPlayedTimestampPrefix =
      'last_played_'; // New key for timestamps
  static const completionPrefix = 'completion_';
  static const completedBooksKey =
      'completed_books'; // New key for completed books
  static const bookmarksKey = 'bookmarks'; // New key for bookmarks
  static const reviewsKey = 'audiobook_reviews'; // Key for book reviews
  static const bookmarksPrefix = 'bookmarks_'; // Prefix for individual audiobook bookmarks
  static const backupSuffix = '_backup';
  static const dataVersionKey = 'data_version';
  static const cacheSyncTimestampKey = 'cache_sync_timestamp';
  static const playbackSpeedPrefix = 'playback_speed_';
  static const durationModePrefix = 'duration_mode_'; // New key for duration mode preference

  
  // Tag-related keys (from tag provider)
  static const userTagsKey = 'user_tags';
  static const audiobookTagsKey = 'audiobook_tags';
  
  // FILE TRACKING SYSTEM KEYS 🐛
  static const fileTrackingKey = 'file_tracking_v2';
  static const pathMigrationsKey = 'path_migrations';
  static const contentHashesKey = 'content_hashes';

  // In-memory cache for reviews
  Map<String, Map<String, dynamic>> _reviewsCache = {};
  bool _reviewsLoaded = false;


  // Singleton instance for this service 
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal() {
    // Start periodic cache persistence
    _startPeriodicCachePersistence();
  }

  // Cached SharedPreferences instance
  SharedPreferences? _prefs;
  
  // In-memory caches to reduce disk access
  final Map<String, double> _progressCache = {};
  final Map<String, Map<String, dynamic>> _positionCache = {};
  final Map<String, int> _timestampCache = {};
  final Set<String> _completedBooksCache = {};
  Map<String, String> _customTitlesCache = {};
  Map<String, double> _playbackSpeedCache = {};
  bool _playbackSpeedLoaded = false;
  List<String> _foldersCache = [];
  
  // EQ Settings Cache
  final Map<String, Map<String, dynamic>> _eqSettingsCache = {};
  
  // FILE TRACKING CACHES 🐛
  Map<String, Map<String, dynamic>> _fileTrackingCache = {}; // path -> metadata
  Map<String, String> _pathMigrationsCache = {}; // oldPath -> newPath
  Map<String, String> _contentHashesCache = {}; // hash -> currentPath

  
  // Cache dirty flags to track which caches need persisting
  final Set<String> _dirtyProgressCache = {};
  final Set<String> _dirtyPositionCache = {};
  final Set<String> _dirtyTimestampCache = {};
  final Set<String> _dirtyPlaybackSpeedCache = {};
  bool _dirtyCompletedBooksCache = false;
  bool _dirtyCustomTitlesCache = false;
  bool _dirtyFoldersCache = false;
  
  // FILE TRACKING DIRTY FLAGS 🐛
  bool _dirtyFileTrackingCache = false;
  bool _dirtyPathMigrationsCache = false;
  bool _dirtyContentHashesCache = false;


  // Periodic timer for cache persistence
  Timer? _cachePersistenceTimer;
  
  // Current data version (increment when making incompatible changes)
  static const int currentDataVersion = 1;
  
  // Flag for whether a cache recovery has been attempted
  bool _recoveryAttempted = false;

  // Start a timer to periodically persist cache to disk
  void _startPeriodicCachePersistence() {
    _cachePersistenceTimer?.cancel();
    _cachePersistenceTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _persistDirtyCaches(),
    );
  }

  // Persist any dirty caches to disk
  Future<void> _persistDirtyCaches() async {
    try {
      if (!_dirtyProgressCache.isEmpty ||
          !_dirtyPositionCache.isEmpty ||
          !_dirtyTimestampCache.isEmpty ||
          !_dirtyPlaybackSpeedCache.isEmpty ||
          _dirtyCompletedBooksCache ||
          _dirtyCustomTitlesCache ||
          _dirtyFoldersCache) {
        debugPrint('Persisting dirty caches to disk...');
        
        final prefs = await _preferences;
        
        // Persist progress cache
        for (final audiobookId in _dirtyProgressCache.toList()) {
          if (_progressCache.containsKey(audiobookId)) {
            final key = '$progressCachePrefix$audiobookId';
            await prefs.setDouble(key, _progressCache[audiobookId]!);
          }
        }
        _dirtyProgressCache.clear();
        
        for (final audiobookId in _dirtyPlaybackSpeedCache.toList()) {
          if (_playbackSpeedCache.containsKey(audiobookId)) {
            final key = '$playbackSpeedPrefix$audiobookId';
            await prefs.setDouble(key, _playbackSpeedCache[audiobookId]!);
          }
        }
        _dirtyPlaybackSpeedCache.clear();
        
        // Persist position cache
        for (final audiobookId in _dirtyPositionCache.toList()) {
          if (_positionCache.containsKey(audiobookId)) {
            final key = '$lastPositionPrefix$audiobookId';
            final data = _positionCache[audiobookId]!;
            final chapterId = data['chapterId'] as String;
            final position = data['position'] as Duration;
            await prefs.setString(key, '$chapterId|${position.inMilliseconds}');
          }
        }
        _dirtyPositionCache.clear();
        
        // Persist timestamp cache
        for (final audiobookId in _dirtyTimestampCache.toList()) {
          if (_timestampCache.containsKey(audiobookId)) {
            final key = '$lastPlayedTimestampPrefix$audiobookId';
            await prefs.setInt(key, _timestampCache[audiobookId]!);
          }
        }
        _dirtyTimestampCache.clear();
        
        // Persist completed books cache
        if (_dirtyCompletedBooksCache) {
          await prefs.setStringList(completedBooksKey, _completedBooksCache.toList());
          _dirtyCompletedBooksCache = false;
        }
        
        // Persist custom titles cache
        if (_dirtyCustomTitlesCache) {
          await _saveCustomTitlesToPrefs();
          _dirtyCustomTitlesCache = false;
        }
        
        // Persist folders cache
        if (_dirtyFoldersCache) {
          await prefs.setStringList(foldersKey, _foldersCache);
          _dirtyFoldersCache = false;
        }
        
        // Persist file tracking caches 🐛
        if (_dirtyFileTrackingCache) {
          await prefs.setString(fileTrackingKey, jsonEncode(_fileTrackingCache));
          _dirtyFileTrackingCache = false;
        }
        
        if (_dirtyPathMigrationsCache) {
          await prefs.setString(pathMigrationsKey, jsonEncode(_pathMigrationsCache));
          _dirtyPathMigrationsCache = false;
        }
        
        if (_dirtyContentHashesCache) {
          await prefs.setString(contentHashesKey, jsonEncode(_contentHashesCache));
          _dirtyContentHashesCache = false;
        }
        

        
        // Update cache sync timestamp
        await prefs.setInt(cacheSyncTimestampKey, DateTime.now().millisecondsSinceEpoch);
        
        debugPrint('Cache persisted successfully.');
      }
    } catch (e) {
      debugPrint('Error persisting caches: $e');
    }
  }

  // Force immediate cache persistence
  Future<void> forcePersistCaches() async {
    return _persistDirtyCaches();
  }

  // Create backup of key data
  Future<void> createDataBackup() async {
    try {
      final prefs = await _preferences;
      
      // Backup progress cache
      for (final key in prefs.getKeys()) {
        if (key.startsWith(progressCachePrefix)) {
          final value = prefs.getDouble(key);
          if (value != null) {
            await prefs.setDouble('$key$backupSuffix', value);
          }
        }
      }
      
      // Backup position data
      for (final key in prefs.getKeys()) {
        if (key.startsWith(lastPositionPrefix)) {
          final value = prefs.getString(key);
          if (value != null) {
            await prefs.setString('$key$backupSuffix', value);
          }
        }
      }
      
      // Backup completed books
      final completedBooks = prefs.getStringList(completedBooksKey);
      if (completedBooks != null) {
        await prefs.setStringList('$completedBooksKey$backupSuffix', completedBooks);
      }
      
      // Backup custom titles
      final customTitlesList = prefs.getStringList(customTitlesKey);
      if (customTitlesList != null) {
        await prefs.setStringList('$customTitlesKey$backupSuffix', customTitlesList);
      }
      
      // Backup folders
      final folders = prefs.getStringList(foldersKey);
      if (folders != null) {
        await prefs.setStringList('$foldersKey$backupSuffix', folders);
      }
      
      // Backup bookmarks
      for (final key in prefs.getKeys()) {
        if (key.startsWith('$bookmarksKey:')) {
          final value = prefs.getString(key);
          if (value != null) {
            await prefs.setString('$key$backupSuffix', value);
          }
        }
      }
      
      // Backup user tags
      final userTags = prefs.getString(userTagsKey);
      if (userTags != null) {
        await prefs.setString('$userTagsKey$backupSuffix', userTags);
      }
      
      // Backup audiobook tags (favorites and other tag assignments)
      final audiobookTags = prefs.getString(audiobookTagsKey);
      if (audiobookTags != null) {
        await prefs.setString('$audiobookTagsKey$backupSuffix', audiobookTags);
      }

      // Backup playback speeds
      for (final key in prefs.getKeys()) {
        if (key.startsWith(playbackSpeedPrefix)) {
          final value = prefs.getDouble(key);
          if (value != null) {
            await prefs.setDouble('$key$backupSuffix', value);
          }
        }
      }
      
      // Backup reading statistics
      for (final key in prefs.getKeys()) {
        if (key.startsWith('reading_session_') || 
            key.startsWith('daily_stats_') ||
            key == 'reading_streak' ||
            key == 'active_session') {
          final value = prefs.getString(key);
          if (value != null) {
            await prefs.setString('$key$backupSuffix', value);
          }
        }
      }
      
      // Backup achievements (CRITICAL: was missing)
      final achievements = prefs.getString('unlocked_achievements');
      if (achievements != null) {
        await prefs.setString('unlocked_achievements$backupSuffix', achievements);
      }
      final achievementTimestamp = prefs.getInt('achievement_last_check');
      if (achievementTimestamp != null) {
        await prefs.setInt('achievement_last_check$backupSuffix', achievementTimestamp);
      }
      
      // Backup statistics settings (daily goal, show streak)
      final dailyGoal = prefs.getInt('daily_reading_goal');
      if (dailyGoal != null) {
        await prefs.setInt('daily_reading_goal$backupSuffix', dailyGoal);
      }
      final showStreak = prefs.getBool('show_reading_streak');
      if (showStreak != null) {
        await prefs.setBool('show_reading_streak$backupSuffix', showStreak);
      }
      
      debugPrint('Data backup created successfully.');
    } catch (e) {
      debugPrint('Error creating data backup: $e');
    }
  }


  // Restore data from backup
  Future<bool> restoreFromBackup() async {
    if (_recoveryAttempted) {
      debugPrint('Recovery already attempted in this session, skipping...');
      return false;
    }
    
    _recoveryAttempted = true;
    bool restoredAnyData = false;
    
    try {
      final prefs = await _preferences;
      
      // Restore progress cache
      for (final key in prefs.getKeys()) {
        if (key.endsWith(backupSuffix) && key.startsWith(progressCachePrefix)) {
          final originalKey = key.substring(0, key.length - backupSuffix.length);
          final value = prefs.getDouble(key);
          if (value != null) {
            await prefs.setDouble(originalKey, value);
            restoredAnyData = true;
          }
        }
      }
      
      // Restore position data
      for (final key in prefs.getKeys()) {
        if (key.endsWith(backupSuffix) && key.startsWith(lastPositionPrefix)) {
          final originalKey = key.substring(0, key.length - backupSuffix.length);
          final value = prefs.getString(key);
          if (value != null) {
            await prefs.setString(originalKey, value);
            restoredAnyData = true;
          }
        }
      }
      
      // Restore completed books
      final completedBooksBackup = prefs.getStringList('$completedBooksKey$backupSuffix');
      if (completedBooksBackup != null) {
        await prefs.setStringList(completedBooksKey, completedBooksBackup);
        restoredAnyData = true;
      }
      
      // Restore custom titles
      final customTitlesBackup = prefs.getStringList('$customTitlesKey$backupSuffix');
      if (customTitlesBackup != null) {
        await prefs.setStringList(customTitlesKey, customTitlesBackup);
        restoredAnyData = true;
      }
      
      // Restore folders
      final foldersBackup = prefs.getStringList('$foldersKey$backupSuffix');
      if (foldersBackup != null) {
        await prefs.setStringList(foldersKey, foldersBackup);
        restoredAnyData = true;
      }
      
      // Restore bookmarks
      for (final key in prefs.getKeys()) {
        if (key.endsWith(backupSuffix) && key.startsWith('$bookmarksKey:')) {
          final originalKey = key.substring(0, key.length - backupSuffix.length);
          final value = prefs.getString(key);
          if (value != null) {
            await prefs.setString(originalKey, value);
            restoredAnyData = true;
          }
        }
      }
      
      // Restore user tags
      final userTagsBackup = prefs.getString('$userTagsKey$backupSuffix');
      if (userTagsBackup != null) {
        await prefs.setString(userTagsKey, userTagsBackup);
        restoredAnyData = true;
      }
      
      // Restore audiobook tags (favorites and other tag assignments)
      final audiobookTagsBackup = prefs.getString('$audiobookTagsKey$backupSuffix');
      if (audiobookTagsBackup != null) {
        await prefs.setString(audiobookTagsKey, audiobookTagsBackup);
        restoredAnyData = true;
      }

      // Restore playback speeds
      for (final key in prefs.getKeys()) {
        if (key.endsWith(backupSuffix) && key.startsWith(playbackSpeedPrefix)) {
          final originalKey = key.substring(0, key.length - backupSuffix.length);
          final value = prefs.getDouble(key);
          if (value != null) {
            await prefs.setDouble(originalKey, value);
            restoredAnyData = true;
          }
        }
      }
      
      // Restore reading statistics
      for (final key in prefs.getKeys()) {
        if (key.endsWith(backupSuffix) && 
            (key.startsWith('reading_session_') || 
             key.startsWith('daily_stats_') ||
             key.contains('reading_streak') ||
             key.contains('active_session'))) {
          final originalKey = key.substring(0, key.length - backupSuffix.length);
          final value = prefs.getString(key);
          if (value != null) {
            await prefs.setString(originalKey, value);
            restoredAnyData = true;
          }
        }
      }
      
      // Restore achievements (CRITICAL: was missing)
      final achievementsBackup = prefs.getString('unlocked_achievements$backupSuffix');
      if (achievementsBackup != null) {
        await prefs.setString('unlocked_achievements', achievementsBackup);
        restoredAnyData = true;
      }
      final achievementTimestampBackup = prefs.getInt('achievement_last_check$backupSuffix');
      if (achievementTimestampBackup != null) {
        await prefs.setInt('achievement_last_check', achievementTimestampBackup);
        restoredAnyData = true;
      }
      
      // Restore statistics settings (daily goal, show streak)
      final dailyGoalBackup = prefs.getInt('daily_reading_goal$backupSuffix');
      if (dailyGoalBackup != null) {
        await prefs.setInt('daily_reading_goal', dailyGoalBackup);
        restoredAnyData = true;
      }
      final showStreakBackup = prefs.getBool('show_reading_streak$backupSuffix');
      if (showStreakBackup != null) {
        await prefs.setBool('show_reading_streak', showStreakBackup);
        restoredAnyData = true;
      }
      
      if (restoredAnyData) {
        debugPrint('Data restored successfully from backup.');
        
        // Clear in-memory caches to force reload from restored data
        _progressCache.clear();
        _positionCache.clear();
        _timestampCache.clear();
        _completedBooksCache.clear();
        _customTitlesCache.clear();
        _foldersCache.clear();
        _playbackSpeedCache.clear();
        
        // Notify listeners that data has been restored
        _notifyRestoreListeners();
        
        return true;
      } else {
        debugPrint('No backup data found or needed for restoration.');
        return false;
      }
    } catch (e) {
      debugPrint('Error restoring data from backup: $e');
      return false;
    }
  }

  // Check data integrity and health
  Future<Map<String, dynamic>> checkDataHealth() async {
    final result = <String, dynamic>{};
    try {
      final prefs = await _preferences;
      
      // Check data version
      final dataVersion = prefs.getInt(dataVersionKey) ?? 0;
      result['dataVersion'] = dataVersion;
      result['currentVersion'] = currentDataVersion;
      result['needsMigration'] = dataVersion < currentDataVersion;
      
      // Count all data types
      int progressCount = 0;
      int positionCount = 0;
      int bookmarkCount = 0;
      int completedBooksCount = 0;
      
      for (final key in prefs.getKeys()) {
        if (key.startsWith(progressCachePrefix)) progressCount++;
        if (key.startsWith(lastPositionPrefix)) positionCount++;
        if (key.startsWith(playbackSpeedPrefix)) progressCount++; // Count playback speeds
        if (key.startsWith('$bookmarksKey:')) bookmarkCount++;
      }
      
      completedBooksCount = (prefs.getStringList(completedBooksKey) ?? []).length;
      final foldersCount = (prefs.getStringList(foldersKey) ?? []).length;
      final customTitlesCount = (prefs.getStringList(customTitlesKey) ?? []).length;
      
      // Count tags
      int userTagsCount = 0;
      int audiobookTagAssignmentsCount = 0;
      
      final userTagsJson = prefs.getString(userTagsKey);
      if (userTagsJson != null) {
        try {
          final tagsList = jsonDecode(userTagsJson) as List;
          userTagsCount = tagsList.length;
        } catch (e) {
          // Invalid JSON, count as 0
        }
      }
      
      final audiobookTagsJson = prefs.getString(audiobookTagsKey);
      if (audiobookTagsJson != null) {
        try {
          final tagsMap = jsonDecode(audiobookTagsJson) as Map<String, dynamic>;
          audiobookTagAssignmentsCount = tagsMap.length;
        } catch (e) {
          // Invalid JSON, count as 0
        }
      }
      
      // Count reading statistics
      int readingSessionsCount = 0;
      int dailyStatsCount = 0;
      for (final key in prefs.getKeys()) {
        if (key.startsWith('reading_session_')) readingSessionsCount++;
        if (key.startsWith('daily_stats_')) dailyStatsCount++;
      }
      
      result['counts'] = {
        'progress': progressCount,
        'positions': positionCount,
        'bookmarks': bookmarkCount,
        'completedBooks': completedBooksCount,
        'folders': foldersCount,
        'customTitles': customTitlesCount,
        'userTags': userTagsCount,
        'audiobookTagAssignments': audiobookTagAssignmentsCount,
        'readingSessions': readingSessionsCount,
        'dailyStats': dailyStatsCount,
      };
      
      // Get last cache sync timestamp
      final lastSyncTimestamp = prefs.getInt(cacheSyncTimestampKey) ?? 0;
      if (lastSyncTimestamp > 0) {
        final lastSyncDate = DateTime.fromMillisecondsSinceEpoch(lastSyncTimestamp);
        result['lastCacheSync'] = lastSyncDate.toString();
      } else {
        result['lastCacheSync'] = 'Never';
      }
      
      debugPrint('Data health check: $result');
      return result;
    } catch (e) {
      debugPrint('Error checking data health: $e');
      result['error'] = e.toString();
      return result;
    }
  }

  // Initialization method to ensure the SharedPreferences instance exists
  Future<SharedPreferences> get _preferences async {
    if (_prefs == null) {
      _prefs = await SharedPreferences.getInstance();
      
      // Check data version and perform migration if needed
      final dataVersion = _prefs!.getInt(dataVersionKey) ?? 0;
      if (dataVersion < currentDataVersion) {
        await _migrateData(dataVersion);
        await _prefs!.setInt(dataVersionKey, currentDataVersion);
      }
      
      // Try to recover from backup if data seems damaged
      if (await _dataLooksCorrupted()) {
        debugPrint('Data appears to be corrupted, attempting recovery...');
        await restoreFromBackup();
      }
      
      // Load initial caches
      _completedBooksCache.addAll(_prefs!.getStringList(completedBooksKey) ?? []);
      _foldersCache = _prefs!.getStringList(foldersKey) ?? [];
      _playbackSpeedCache = Map.fromEntries(_prefs!.getKeys()
          .where((key) => key.startsWith(playbackSpeedPrefix))
          .map((key) => MapEntry(key.substring(playbackSpeedPrefix.length),
              _prefs!.getDouble(key) ?? 1.0)));
      
      // Load custom titles
      await loadCustomTitles();
    }
    return _prefs!;
  }
  
  // Check if data appears to be corrupted
  Future<bool> _dataLooksCorrupted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check if folders exist but completed books key doesn't
      final hasFolders = prefs.containsKey(foldersKey);
      final hasCompletedBooks = prefs.containsKey(completedBooksKey);
      
      if (hasFolders && !hasCompletedBooks && prefs.containsKey('$completedBooksKey$backupSuffix')) {
        return true;
      }
      
      // Check if folders exist but no progress data exists
      final folderList = prefs.getStringList(foldersKey) ?? [];
      if (folderList.isNotEmpty) {
        bool hasAnyProgressData = false;
        for (final folder in folderList) {
          final progressKey = '$progressCachePrefix$folder';
          if (prefs.containsKey(progressKey)) {
            hasAnyProgressData = true;
            break;
          }
        }
        
        if (!hasAnyProgressData) {
          // Check if backup exists
          for (final folder in folderList) {
            final backupKey = '$progressCachePrefix$folder$backupSuffix';
            if (prefs.containsKey(backupKey)) {
              return true;
            }
          }
        }
      }
      
      return false;
    } catch (e) {
      debugPrint('Error checking data corruption: $e');
      return false;
    }
  }

  // Migrate data between versions
  Future<void> _migrateData(int fromVersion) async {
    try {
      debugPrint('Migrating data from version $fromVersion to $currentDataVersion');
      
      // Backup current data before migration
      await createDataBackup();
      
      // Add migration steps here when needed in the future
      // if (fromVersion < 1) {
      //   await _migrateFromV0ToV1();
      // }
      // if (fromVersion < 2) {
      //   await _migrateFromV1ToV2();
      // }
      
      debugPrint('Data migration completed successfully');
    } catch (e) {
      debugPrint('Error during data migration: $e');
    }
  }

  /// Saves a list of audiobook folder paths to shared preferences
  Future<void> saveAudiobookFolders(List<String> paths) async {
    try {
      final prefs = await _preferences;
      await prefs.setStringList(foldersKey, paths);
      
      // Update cache and mark as not dirty
      _foldersCache = paths;
      _dirtyFoldersCache = false;
      
      debugPrint("Saved audiobook folders: $paths");
    } catch (e) {
      debugPrint("Error saving audiobook folders: $e");
    }
  }

  /// Saves the library view mode preference (true for grid, false for list)
  Future<void> saveViewModePreference(bool isGridView) async {
    try {
      final prefs = await _preferences;
      await prefs.setBool('library_is_grid_view', isGridView);
      debugPrint("Saved view mode preference: ${isGridView ? 'Grid' : 'List'}");
    } catch (e) {
      debugPrint("Error saving view mode preference: $e");
    }
  }

  /// Loads the library view mode preference
  Future<bool> loadViewModePreference() async {
    try {
      final prefs = await _preferences;
      // Default to List view (false) if not set
      return prefs.getBool('library_is_grid_view') ?? false;
    } catch (e) {
      debugPrint("Error loading view mode preference: $e");
      return false;
    }
  }

  // Notifications
  static const String _notificationsEnabledKey = 'notifications_enabled';

  Future<bool> getNotificationsEnabled() async {
    final prefs = await _preferences;
    return prefs.getBool(_notificationsEnabledKey) ?? true;
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await _preferences;
    await prefs.setBool(_notificationsEnabledKey, enabled);
  }

  // Equalizer Settings (GLOBAL - kept for backwards compat, but deprecated)
  static const String _eqEnabledKey = 'eq_enabled';
  static const String _eqBoostKey = 'eq_boost';
  static const String _eqBandsKey = 'eq_bands_gain';

  // Per-Book Equalizer Settings
  static const String _eqBookPrefix = 'eq_book_';

  Future<bool> getEqualizerEnabled({String? audiobookId}) async {
    if (audiobookId != null && _eqSettingsCache.containsKey(audiobookId)) {
      return _eqSettingsCache[audiobookId]!['enabled'] as bool? ?? false;
    }
    final prefs = await _preferences;
    if (audiobookId != null) {
      return prefs.getBool('${_eqBookPrefix}${audiobookId}_enabled') ?? false;
    }
    return prefs.getBool(_eqEnabledKey) ?? false;
  }

  Future<void> saveEqualizerEnabled(bool enabled, {String? audiobookId}) async {
    final prefs = await _preferences;
    if (audiobookId != null) {
      if (!_eqSettingsCache.containsKey(audiobookId)) {
        await getBookEqualizerSettings(audiobookId); // Load full set first to ensure we don't partial-overwrite cache
      }
      _eqSettingsCache[audiobookId]!['enabled'] = enabled;
      await prefs.setBool('${_eqBookPrefix}${audiobookId}_enabled', enabled);
    } else {
      await prefs.setBool(_eqEnabledKey, enabled);
    }
  }

  Future<double> getVolumeBoost({String? audiobookId}) async {
    if (audiobookId != null && _eqSettingsCache.containsKey(audiobookId)) {
      return _eqSettingsCache[audiobookId]!['boost'] as double? ?? 0.0;
    }
    final prefs = await _preferences;
    if (audiobookId != null) {
      return prefs.getDouble('${_eqBookPrefix}${audiobookId}_boost') ?? 0.0;
    }
    return prefs.getDouble(_eqBoostKey) ?? 0.0;
  }

  Future<void> saveVolumeBoost(double boost, {String? audiobookId}) async {
    final prefs = await _preferences;
    if (audiobookId != null) {
      if (!_eqSettingsCache.containsKey(audiobookId)) {
        await getBookEqualizerSettings(audiobookId);
      }
      _eqSettingsCache[audiobookId]!['boost'] = boost;
      await prefs.setDouble('${_eqBookPrefix}${audiobookId}_boost', boost);
    } else {
      await prefs.setDouble(_eqBoostKey, boost);
    }
  }

  Future<void> saveEqualizerBandGain(int bandIndex, double gain, {String? audiobookId}) async {
    final prefs = await _preferences;
    if (audiobookId != null) {
      if (!_eqSettingsCache.containsKey(audiobookId)) {
        await getBookEqualizerSettings(audiobookId);
      }
      final bands = _eqSettingsCache[audiobookId]!['bands'] as Map<int, double>;
      bands[bandIndex] = gain;
      await prefs.setString('${_eqBookPrefix}${audiobookId}_bands', jsonEncode(bands.map((k, v) => MapEntry(k.toString(), v))));
    } else {
      final jsonString = prefs.getString(_eqBandsKey);
      Map<String, dynamic> bands = {};
      if (jsonString != null) {
        try {
          bands = jsonDecode(jsonString) as Map<String, dynamic>;
        } catch (e) {}
      }
      bands[bandIndex.toString()] = gain;
      await prefs.setString(_eqBandsKey, jsonEncode(bands));
    }
  }
  
  Future<Map<int, double>> getEqualizerBandGains({String? audiobookId}) async {
    if (audiobookId != null && _eqSettingsCache.containsKey(audiobookId)) {
      return _eqSettingsCache[audiobookId]!['bands'] as Map<int, double>? ?? {};
    }
    final prefs = await _preferences;
    final key = audiobookId != null 
        ? '${_eqBookPrefix}${audiobookId}_bands' 
        : _eqBandsKey;
    final jsonString = prefs.getString(key);
    if (jsonString == null) return {};
    
    try {
      final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
      final result = jsonMap.map((k, v) => MapEntry(int.parse(k), (v as num).toDouble())); 
      
      // If we loaded specifically for a book, we SHOULD NOT populate the whole cache here
      // because getBookEqualizerSettings handles that more safely. 
      // But we can return the result.
      return result;
    } catch (e) {
      return {};
    }
  }

  /// Save complete EQ settings for a book (for efficiency)
  Future<void> saveBookEqualizerSettings(String audiobookId, {
    required bool enabled,
    required double boost,
    required Map<int, double> bandGains,
  }) async {
    _eqSettingsCache[audiobookId] = {
      'enabled': enabled,
      'boost': boost,
      'bands': bandGains,
    };
    
    final prefs = await _preferences;
    await prefs.setBool('${_eqBookPrefix}${audiobookId}_enabled', enabled);
    await prefs.setDouble('${_eqBookPrefix}${audiobookId}_boost', boost);
    final bandsJson = bandGains.map((k, v) => MapEntry(k.toString(), v));
    await prefs.setString('${_eqBookPrefix}${audiobookId}_bands', jsonEncode(bandsJson));
  }

  /// Load complete EQ settings for a book
  Future<Map<String, dynamic>> getBookEqualizerSettings(String audiobookId) async {
    if (_eqSettingsCache.containsKey(audiobookId)) {
      return _eqSettingsCache[audiobookId]!;
    }
    
    final prefs = await _preferences;
    final settings = {
      'enabled': prefs.getBool('${_eqBookPrefix}${audiobookId}_enabled') ?? false,
      'boost': prefs.getDouble('${_eqBookPrefix}${audiobookId}_boost') ?? 0.0,
      'bands': await getEqualizerBandGains(audiobookId: audiobookId),
    };
    
    _eqSettingsCache[audiobookId] = settings;
    return settings;
  }

  /// Loads list of audiobook folder paths from shared preferences
  Future<List<String>> loadAudiobookFolders() async {
    try {
      // Check cache first
      if (_foldersCache.isNotEmpty) {
        return _foldersCache;
      }
      
      final prefs = await _preferences;
      final folders = prefs.getStringList(foldersKey) ?? [];
      
      // Apply path migrations if any exist
      final migratedFolders = await _applyPathMigrations(folders);
      
      // Update cache
      _foldersCache = migratedFolders;
      _dirtyFoldersCache = false;
      
      debugPrint("Loaded audiobook folders: $migratedFolders");
      return migratedFolders;
    } catch (e) {
      debugPrint("Error loading audiobook folders: $e");
      return []; // Return empty list on error
    }
  }

  // 🐛 FILE TRACKING SYSTEM IMPLEMENTATION
  
  /// Generate content-based hash for an audiobook folder
  /// Uses first and last audio file info + folder structure for fingerprinting
  Future<String> generateContentHash(String folderPath) async {
    try {
      final directory = Directory(folderPath);
      if (!await directory.exists()) {
        return '';
      }

      final List<FileSystemEntity> files = await directory.list().toList();
      final audioFiles = files
          .whereType<File>()
          .where((file) => _isAudioFile(file.path))
          .toList();

      if (audioFiles.isEmpty) {
        return '';
      }

      // Sort for consistent ordering
      audioFiles.sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

      // Create hash from:
      // 1. Folder name
      // 2. Number of audio files  
      // 3. First file name and size
      // 4. Last file name and size
      // 5. Total folder size (approximate)

      final folderName = path.basename(folderPath);
      final fileCount = audioFiles.length;
      
      final firstFile = audioFiles.first;
      final lastFile = audioFiles.last;
      
      final firstFileInfo = '${path.basename(firstFile.path)}_${await firstFile.length()}';
      final lastFileInfo = '${path.basename(lastFile.path)}_${await lastFile.length()}';
      
      // Calculate approximate total size from sample files
      int totalSize = 0;
      final sampleSize = (audioFiles.length / 5).ceil().clamp(1, 10);
      for (int i = 0; i < sampleSize && i < audioFiles.length; i += audioFiles.length ~/ sampleSize) {
        totalSize += await audioFiles[i].length();
      }

      final hashInput = '$folderName|$fileCount|$firstFileInfo|$lastFileInfo|$totalSize';
      final hash = hashInput.hashCode.abs().toString();
      
      debugPrint("Generated content hash for $folderPath: $hash");
      return hash;
      
    } catch (e) {
      debugPrint("Error generating content hash for $folderPath: $e");
      return '';
    }
  }

  /// Check if file is an audio file
  bool _isAudioFile(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    return ['.mp3', '.m4a', '.m4b', '.wav', '.ogg', '.aac', '.flac', '.opus'].contains(extension);
  }

  /// Register a new audiobook with robust tracking
  Future<void> registerAudiobook(String folderPath, {
    String? title,
    String? author,
    int? chapterCount,
  }) async {
    try {
      // Generate content hash
      final contentHash = await generateContentHash(folderPath);
      
      if (contentHash.isEmpty) {
        debugPrint("Could not generate content hash for $folderPath");
        return;
      }

      // Store file tracking metadata
      final trackingData = {
        'originalPath': folderPath,
        'currentPath': folderPath,
        'contentHash': contentHash,
        'title': title ?? path.basename(folderPath),
        'author': author,
        'chapterCount': chapterCount ?? 0,
        'registeredAt': DateTime.now().millisecondsSinceEpoch,
        'lastVerified': DateTime.now().millisecondsSinceEpoch,
      };

      _fileTrackingCache[folderPath] = trackingData;
      _contentHashesCache[contentHash] = folderPath;
      _dirtyFileTrackingCache = true;
      _dirtyContentHashesCache = true;

      debugPrint("Registered audiobook: $folderPath with hash: $contentHash");
      
    } catch (e) {
      debugPrint("Error registering audiobook $folderPath: $e");
    }
  }

  /// Find audiobook by content hash (for moved/renamed detection)
  Future<String?> findAudiobookByContentHash(String contentHash) async {
    await _loadFileTrackingCaches();
    return _contentHashesCache[contentHash];
  }

  /// Attempt to locate a missing audiobook folder
  Future<String?> locateMissingAudiobook(String missingPath) async {
    try {
      debugPrint("Attempting to locate missing audiobook: $missingPath");
      
      // Load tracking data
      await _loadFileTrackingCaches();
      
      // Check if we have tracking data for this path
      final trackingData = _fileTrackingCache[missingPath];
      if (trackingData == null) {
        debugPrint("No tracking data found for $missingPath");
        return null;
      }

      final expectedHash = trackingData['contentHash'] as String?;
      if (expectedHash == null) {
        debugPrint("No content hash in tracking data for $missingPath");
        return null;
      }

      // Strategy 1: Check if path migration exists
      final migratedPath = _pathMigrationsCache[missingPath];
      if (migratedPath != null && await Directory(migratedPath).exists()) {
        final currentHash = await generateContentHash(migratedPath);
        if (currentHash == expectedHash) {
          debugPrint("Found via path migration: $missingPath -> $migratedPath");
          return migratedPath;
        }
      }

      // Strategy 2: Check content hash lookup
      final hashPath = _contentHashesCache[expectedHash];
      if (hashPath != null && hashPath != missingPath && await Directory(hashPath).exists()) {
        final currentHash = await generateContentHash(hashPath);
        if (currentHash == expectedHash) {
          debugPrint("Found via content hash: $missingPath -> $hashPath");
          await _recordPathMigration(missingPath, hashPath);
          return hashPath;
        }
      }

      // Strategy 3: Search in parent directory for matching folder
      final parentDir = Directory(path.dirname(missingPath));
      if (await parentDir.exists()) {
        await for (final entity in parentDir.list()) {
          if (entity is Directory) {
            final currentHash = await generateContentHash(entity.path);
            if (currentHash == expectedHash) {
              debugPrint("Found via parent search: $missingPath -> ${entity.path}");
              await _recordPathMigration(missingPath, entity.path);
              return entity.path;
            }
          }
        }
      }

      // Strategy 4: Broader search in common audiobook locations
      final title = trackingData['title'] as String?;
      if (title != null) {
        final foundPath = await _searchForAudiobookByTitle(title, expectedHash);
        if (foundPath != null) {
          debugPrint("Found via title search: $missingPath -> $foundPath");
          await _recordPathMigration(missingPath, foundPath);
          return foundPath;
        }
      }

      debugPrint("Could not locate missing audiobook: $missingPath");
      
      return null;
      
    } catch (e) {
      debugPrint("Error locating missing audiobook $missingPath: $e");
      return null;
    }
  }

  /// Search for audiobook by title in common locations
  Future<String?> _searchForAudiobookByTitle(String title, String expectedHash) async {
    try {
      // Search in common audiobook directories
      final commonPaths = [
        '/storage/emulated/0/Audiobooks',
        '/storage/emulated/0/Downloads',
        '/storage/emulated/0/Music',
        '/storage/emulated/0',
      ];

      for (final commonPath in commonPaths) {
        final commonDir = Directory(commonPath);
        if (await commonDir.exists()) {
          await for (final entity in commonDir.list(recursive: true)) {
            if (entity is Directory && path.basename(entity.path).toLowerCase().contains(title.toLowerCase())) {
              final hash = await generateContentHash(entity.path);
              if (hash == expectedHash) {
                return entity.path;
              }
            }
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint("Error searching for audiobook by title: $e");
      return null;
    }
  }

  /// Record a path migration for future reference
  Future<void> _recordPathMigration(String oldPath, String newPath) async {
    _pathMigrationsCache[oldPath] = newPath;
    _dirtyPathMigrationsCache = true;
    
    // Update content hash mapping
    final trackingData = _fileTrackingCache[oldPath];
    if (trackingData != null) {
      trackingData['currentPath'] = newPath;
      trackingData['lastVerified'] = DateTime.now().millisecondsSinceEpoch;
      
      // Move tracking data to new path
      _fileTrackingCache[newPath] = trackingData;
      _fileTrackingCache.remove(oldPath);
      _dirtyFileTrackingCache = true;
      
      // Update content hash lookup
      final contentHash = trackingData['contentHash'] as String?;
      if (contentHash != null) {
        _contentHashesCache[contentHash] = newPath;
        _dirtyContentHashesCache = true;
      }
    }
    
    debugPrint("Recorded path migration: $oldPath -> $newPath");
  }



  /// Apply path migrations to a list of folder paths
  Future<List<String>> _applyPathMigrations(List<String> folders) async {
    await _loadFileTrackingCaches();
    
    final migratedFolders = <String>[];
    bool hasMigrations = false;
    
    for (final folder in folders) {
      final migratedPath = _pathMigrationsCache[folder];
      if (migratedPath != null && await Directory(migratedPath).exists()) {
        migratedFolders.add(migratedPath);
        hasMigrations = true;
        debugPrint("Applied migration: $folder -> $migratedPath");
      } else {
        migratedFolders.add(folder);
      }
    }
    
    // Save updated folders list if we had migrations
    if (hasMigrations) {
      await saveAudiobookFolders(migratedFolders);
    }
    
    return migratedFolders;
  }

  /// Load file tracking caches from storage
  Future<void> _loadFileTrackingCaches() async {
    if (_fileTrackingCache.isNotEmpty) return; // Already loaded
    
    try {
      final prefs = await _preferences;
      
      // Load file tracking data
      final trackingJson = prefs.getString(fileTrackingKey);
      if (trackingJson != null) {
        final trackingMap = jsonDecode(trackingJson) as Map<String, dynamic>;
        _fileTrackingCache = trackingMap.map((key, value) => MapEntry(key, Map<String, dynamic>.from(value)));
      }
      
      // Load path migrations
      final migrationsJson = prefs.getString(pathMigrationsKey);
      if (migrationsJson != null) {
        final migrationsMap = jsonDecode(migrationsJson) as Map<String, dynamic>;
        _pathMigrationsCache = migrationsMap.cast<String, String>();
      }
      
      // Load content hashes
      final hashesJson = prefs.getString(contentHashesKey);
      if (hashesJson != null) {
        final hashesMap = jsonDecode(hashesJson) as Map<String, dynamic>;
        _contentHashesCache = hashesMap.cast<String, String>();
      }
      

      
      debugPrint("Loaded file tracking caches");
      
    } catch (e) {
      debugPrint("Error loading file tracking caches: $e");
    }
  }



  /// Manual path correction by user
  Future<bool> correctAudiobookPath(String oldPath, String newPath) async {
    try {
      if (!await Directory(newPath).exists()) {
        debugPrint("New path does not exist: $newPath");
        return false;
      }

      // Verify it's the same audiobook by generating hash
      final trackingData = _fileTrackingCache[oldPath];
      if (trackingData != null) {
        final expectedHash = trackingData['contentHash'] as String?;
        final currentHash = await generateContentHash(newPath);
        
        if (expectedHash != null && currentHash == expectedHash) {
          await _recordPathMigration(oldPath, newPath);
          

          
          debugPrint("Successfully corrected path: $oldPath -> $newPath");
          return true;
        } else {
          debugPrint("Content hash mismatch. Expected: $expectedHash, Got: $currentHash");
          return false;
        }
      }
      
      return false;
      
    } catch (e) {
      debugPrint("Error correcting audiobook path: $e");
      return false;
    }
  }

  /// Saves the last playback position for a given audiobook chapter.
  /// Requires non-nullable IDs.
  Future<void> saveLastPosition(
    String audiobookId,
    String chapterId,
    Duration position,
  ) async {
    try {
      // Store in both cache and preferences
      _positionCache[audiobookId] = {
        'chapterId': chapterId,
        'position': position
      };
      _dirtyPositionCache.add(audiobookId);
      
      // Also save to disk immediately for critical data
      final prefs = await _preferences;
      final key = '$lastPositionPrefix$audiobookId';
      final value = '$chapterId|${position.inMilliseconds}';
      await prefs.setString(key, value);

      // Clear any cached progress percentage to force recalculation
      await _clearProgressCache(audiobookId);

      // Update last played timestamp whenever position is saved
      await updateLastPlayedTimestamp(audiobookId);

      debugPrint(
        'Saved position for $audiobookId: $chapterId at ${position.inMilliseconds}ms',
      );
    } catch (e) {
      debugPrint("Error saving last position for $audiobookId: $e");
    }
  }

  /// Loads the last playback position (chapter ID and position) for a given audiobook.
  /// Returns null if no position is saved or if data is invalid.
  Future<Map<String, dynamic>?> loadLastPosition(String audiobookId) async {
    try {
      // Check the cache first
      if (_positionCache.containsKey(audiobookId)) {
        debugPrint('Returning cached position data for $audiobookId');
        return _positionCache[audiobookId];
      }
      
      final prefs = await _preferences;
      final key = '$lastPositionPrefix$audiobookId';
      final savedData = prefs.getString(key);

      if (savedData != null) {
        final parts = savedData.split('|');
        // Ensure data format is correct (chapterId|milliseconds)
        if (parts.length == 2) {
          final chapterId = parts[0];
          final positionMillis = int.tryParse(parts[1]);

          if (positionMillis != null && chapterId.isNotEmpty) {
            final position = Duration(milliseconds: positionMillis);
            
            // Update cache
            _positionCache[audiobookId] = {
              'chapterId': chapterId,
              'position': position
            };
            
            debugPrint(
              'Loaded position for $audiobookId: $chapterId at ${position.inMilliseconds}ms',
            );
            return _positionCache[audiobookId];
          } else {
            debugPrint(
              'Invalid position data format for $audiobookId: "$savedData"',
            );
            await clearLastPosition(audiobookId); // Clear invalid data
          }
        } else {
          debugPrint(
            'Invalid position data format for $audiobookId: "$savedData"',
          );
          await clearLastPosition(audiobookId); // Clear invalid data
        }
      } else {
        debugPrint('No saved position found for $audiobookId');
      }
    } catch (e) {
      debugPrint("Error loading last position for $audiobookId: $e");
    }
    return null; // Return null if not found, invalid, or error
  }

  /// Updates the last played timestamp to current time
  Future<void> updateLastPlayedTimestamp(String audiobookId) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      
      // Update cache and mark as dirty
      _timestampCache[audiobookId] = now;
      _dirtyTimestampCache.add(audiobookId);
      
      // Also update in shared preferences
      final prefs = await _preferences;
      final key = '$lastPlayedTimestampPrefix$audiobookId';
      await prefs.setInt(key, now);
      
      debugPrint('Updated last played timestamp for $audiobookId: $now');
    } catch (e) {
      debugPrint("Error saving last played timestamp for $audiobookId: $e");
    }
  }

  /// Gets the last played timestamp for an audiobook
  /// Returns 0 if the book has never been played
  Future<int> getLastPlayedTimestamp(String audiobookId) async {
    try {
      // Check cache first
      if (_timestampCache.containsKey(audiobookId)) {
        return _timestampCache[audiobookId]!;
      }
      
      final prefs = await _preferences;
      final key = '$lastPlayedTimestampPrefix$audiobookId';
      final timestamp = prefs.getInt(key) ?? 0;
      
      // Update cache
      _timestampCache[audiobookId] = timestamp;
      
      return timestamp;
    } catch (e) {
      debugPrint("Error getting last played timestamp for $audiobookId: $e");
      return 0; // Return 0 as default (never played)
    }
  }

  /// Marks an audiobook as completed
  Future<void> markAsCompleted(String audiobookId) async {
    try {
      // Check if it's already in the cache
      if (_completedBooksCache.contains(audiobookId)) {
        return; // Already completed, no need to update
      }
      
      // Update cache and mark as dirty
      _completedBooksCache.add(audiobookId);
      _dirtyCompletedBooksCache = true;
      
      // Also update in shared preferences
      final prefs = await _preferences;
      final completedBooks = prefs.getStringList(completedBooksKey) ?? [];

      if (!completedBooks.contains(audiobookId)) {
        completedBooks.add(audiobookId);
        await prefs.setStringList(completedBooksKey, completedBooks);
        debugPrint('Marked $audiobookId as completed');
      }
    } catch (e) {
      debugPrint("Error marking audiobook as completed: $e");
    }
  }

  /// Removes an audiobook from the completed list
  Future<void> unmarkAsCompleted(String audiobookId) async {
    try {
      // Fast check if it's not in the cache
      if (!_completedBooksCache.contains(audiobookId)) {
        return; // Not completed, no need to update
      }
      
      final prefs = await _preferences;
      final completedBooks = prefs.getStringList(completedBooksKey) ?? [];

      if (completedBooks.contains(audiobookId)) {
        completedBooks.remove(audiobookId);
        await prefs.setStringList(completedBooksKey, completedBooks);
        
        // Update cache
        _completedBooksCache.remove(audiobookId);
        
        debugPrint('Unmarked $audiobookId as completed');
      }
    } catch (e) {
      debugPrint("Error unmarking audiobook as completed: $e");
    }
  }

  /// Checks if an audiobook is marked as completed
  Future<bool> isCompleted(String audiobookId) async {
    try {
      // Check cache first for faster response
      return _completedBooksCache.contains(audiobookId);
    } catch (e) {
      debugPrint("Error checking if audiobook is completed: $e");
      return false;
    }
  }

  /// Gets all completed audiobook IDs
  Future<List<String>> getCompletedBooks() async {
    try {
      // Return from cache if available
      if (_completedBooksCache.isNotEmpty) {
        return _completedBooksCache.toList();
      }
      
      // Otherwise load from preferences
      final prefs = await _preferences;
      final completedBooks = prefs.getStringList(completedBooksKey) ?? [];
      _completedBooksCache.addAll(completedBooks);
      return completedBooks;
    } catch (e) {
      debugPrint("Error getting completed books: $e");
      return [];
    }
  }

  /// Clears the saved playback position for a specific audiobook.
  Future<void> clearLastPosition(String audiobookId) async {
    try {
      final prefs = await _preferences;
      final key = '$lastPositionPrefix$audiobookId';
      await prefs.remove(key);

      // Clear from cache
      _positionCache.remove(audiobookId);

      // Also clear any cached progress
      await _clearProgressCache(audiobookId);

      debugPrint('Cleared position for $audiobookId');
    } catch (e) {
      debugPrint("Error clearing last position for $audiobookId: $e");
    }
  }

  // Save custom titles
  Future<void> saveCustomTitles(Map<String, String> titles) async {
    final prefs = await _preferences;
    _customTitlesCache = Map.from(titles);
    _dirtyCustomTitlesCache = false;
    await prefs.setString(customTitlesKey, jsonEncode(titles));
  }

  /// Save a review for an audiobook
  Future<void> saveAudiobookReview(String audiobookId, double rating, String? reviewContent, {DateTime? timestamp}) async {
    final prefs = await _preferences;
    
    // Ensure cache is loaded
    if (!_reviewsLoaded) {
      await loadAudiobookReviews();
    }
    
    final reviewTime = timestamp ?? DateTime.now();
    
    _reviewsCache[audiobookId] = {
      'rating': rating,
      'review': reviewContent,
      'timestamp': reviewTime.toIso8601String(),
    };
    
    await prefs.setString(reviewsKey, jsonEncode(_reviewsCache));
  }
  
  /// Load all audiobook reviews
  Future<Map<String, Map<String, dynamic>>> loadAudiobookReviews() async {
    if (_reviewsLoaded) {
      return Map.from(_reviewsCache);
    }

    final prefs = await _preferences;
    final jsonString = prefs.getString(reviewsKey);
    
    if (jsonString == null) {
      _reviewsCache = {};
      _reviewsLoaded = true;
      return {};
    }
    
    try {
      final Map<String, dynamic> decoded = jsonDecode(jsonString);
      // Convert to expected types
      final Map<String, Map<String, dynamic>> result = {};
      decoded.forEach((key, value) {
        if (value is Map) {
          result[key] = Map<String, dynamic>.from(value);
        }
      });
      
      _reviewsCache = result;
      _reviewsLoaded = true;
      return result;
    } catch (e) {
      debugPrint('Error loading reviews: $e');
      _reviewsCache = {};
      _reviewsLoaded = true;
      return {};
    }
  }
  
  /// Get review for specific audiobook
  Future<Map<String, dynamic>?> getAudiobookReview(String audiobookId) async {
    // Ensure cache is loaded
    if (!_reviewsLoaded) {
      await loadAudiobookReviews();
    }
    return _reviewsCache[audiobookId];
  }

  /// Loads custom titles for audiobooks
  Future<Map<String, String>> loadCustomTitles() async {
    try {
      // Check cache first
      if (_customTitlesCache.isNotEmpty) {
        return _customTitlesCache;
      }
      
      final prefs = await _preferences;
      final titlesList = prefs.getStringList(customTitlesKey) ?? [];

      // Convert list back to map
      final Map<String, String> customTitles = {};
      for (final item in titlesList) {
        final parts = item.split('|');
        if (parts.length >= 2) {
          // Join any remaining parts in case the title itself contains |
          final id = parts[0];
          final title = parts.sublist(1).join('|');
          customTitles[id] = title;
        }
      }
      
      // Update cache
      _customTitlesCache = customTitles;

      debugPrint("Loaded ${customTitles.length} custom titles");
      return customTitles;
    } catch (e) {
      debugPrint("Error loading custom titles: $e");
      return {}; // Return empty map on error
    }
  }

  /// Saves a cached progress percentage for quicker loading
  Future<void> saveProgressCache(
    String audiobookId,
    double progressPercentage,
  ) async {
    try {
      // Update in-memory cache and mark as dirty
      _progressCache[audiobookId] = progressPercentage;
      _dirtyProgressCache.add(audiobookId);
      
      // Also save to preferences
      final prefs = await _preferences;
      final key = '$progressCachePrefix$audiobookId';
      await prefs.setDouble(key, progressPercentage);
      
      debugPrint(
        'Cached progress for $audiobookId: ${(progressPercentage * 100).toStringAsFixed(1)}%',
      );

      // If progress is 100%, mark book as completed
      if (progressPercentage >= 0.99) {
        await markAsCompleted(audiobookId);
      } else if (progressPercentage > 0) {
        // If book has progress but not completed, ensure it's not in completed list
        await unmarkAsCompleted(audiobookId);
      }
    } catch (e) {
      debugPrint("Error saving progress cache for $audiobookId: $e");
    }
  }

  /// Saves the duration mode preference for a specific audiobook
  Future<void> saveDurationMode(String audiobookId, bool isTotalMode) async {
    try {
      final prefs = await _preferences;
      final key = '$durationModePrefix$audiobookId';
      await prefs.setBool(key, isTotalMode);
      debugPrint("Saved duration mode for $audiobookId: $isTotalMode");
    } catch (e) {
      debugPrint("Error saving duration mode: $e");
    }
  }

  /// Loads the duration mode preference for a specific audiobook
  Future<bool> loadDurationMode(String audiobookId) async {
    try {
      final prefs = await _preferences;
      final key = '$durationModePrefix$audiobookId';
      // Default to false (Chapter Mode) if not found
      return prefs.getBool(key) ?? false;
    } catch (e) {
      debugPrint("Error loading duration mode: $e");
      return false;
    }
  }


  /// Loads a cached progress percentage if available
  Future<double?> loadProgressCache(String audiobookId) async {
    try {
      // Check in-memory cache first
      if (_progressCache.containsKey(audiobookId)) {
        final cachedProgress = _progressCache[audiobookId];
        debugPrint(
          'Using in-memory cached progress for $audiobookId: ${(cachedProgress ?? 0.0) * 100}%',
        );
        return cachedProgress;
      }
      
      final prefs = await _preferences;
      final key = '$progressCachePrefix$audiobookId';
      if (prefs.containsKey(key)) {
        final progress = prefs.getDouble(key);
        
        // Update in-memory cache
        if (progress != null) {
          _progressCache[audiobookId] = progress;
        }
        
        debugPrint(
          'Loaded cached progress for $audiobookId: ${(progress ?? 0.0) * 100}%',
        );
        return progress;
      }
    } catch (e) {
      debugPrint("Error loading progress cache for $audiobookId: $e");
    }
    return null;
  }

  /// Clears the cached progress percentage for an audiobook
  Future<void> _clearProgressCache(String audiobookId) async {
    try {
      final prefs = await _preferences;
      final key = '$progressCachePrefix$audiobookId';
      await prefs.remove(key);
      
      // Clear from in-memory cache
      _progressCache.remove(audiobookId);
      
      debugPrint('Cleared cached progress for $audiobookId');
    } catch (e) {
      debugPrint("Error clearing progress cache for $audiobookId: $e");
    }
  }

  /// Gets all audiobooks that have been listened to since the given date
  Future<List<String>> getAudiobooksPlayedSince(DateTime date) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final results = <String>[];

    for (final key in keys) {
      if (key.startsWith(lastPlayedTimestampPrefix)) {
        final id = key.substring(lastPlayedTimestampPrefix.length);
        final timestamp = prefs.getInt(key);
        if (timestamp != null) {
          final lastPlayed = DateTime.fromMillisecondsSinceEpoch(timestamp);
          if (lastPlayed.isAfter(date)) {
            results.add(id);
          }
        }
      }
    }

    return results;
  }

  /// Save a completion flag for the audiobook
  Future<void> saveCompletionStatus(String audiobookId, bool isCompleted) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final key = '$completionPrefix$audiobookId';
    await prefs.setBool(key, isCompleted);
  }

  // ------ Bookmark Methods ------

  // In-memory cache for bookmarks
  final Map<String, List<Bookmark>> _bookmarksCache = {};

  /// Saves a bookmark
  Future<void> saveBookmark(Bookmark bookmark) async {
    try {
      final prefs = await _preferences;
      
      // Get all current bookmarks
      final bookmarks = await getBookmarks(bookmark.audiobookId);
      
      // Add or replace bookmark
      final existingIndex = bookmarks.indexWhere((b) => b.id == bookmark.id);
      if (existingIndex >= 0) {
        bookmarks[existingIndex] = bookmark;
      } else {
        bookmarks.add(bookmark);
      }
      
      // Convert to map format for storage
      final bookmarkMaps = bookmarks.map((b) => b.toMap()).toList();
      
      // Store all bookmarks for this audiobook
      final key = '$bookmarksKey:${bookmark.audiobookId}';
      await prefs.setString(key, jsonEncode(bookmarkMaps));
      
      // Update cache
      _bookmarksCache[bookmark.audiobookId] = bookmarks;
      
      debugPrint('Saved bookmark "${bookmark.name}" for ${bookmark.audiobookId}');
    } catch (e) {
      debugPrint('Error saving bookmark: $e');
    }
  }

  /// Gets all bookmarks for an audiobook
  Future<List<Bookmark>> getBookmarks(String audiobookId) async {
    try {
      // Check cache first
      if (_bookmarksCache.containsKey(audiobookId)) {
        return _bookmarksCache[audiobookId]!;
      }
      
      final prefs = await _preferences;
      final key = '$bookmarksKey:$audiobookId';
      final bookmarksJson = prefs.getString(key);
      
      if (bookmarksJson != null) {
        // Decode from JSON
        final List<dynamic> bookmarksList = jsonDecode(bookmarksJson);
        final bookmarks = bookmarksList
            .map((map) => Bookmark.fromMap(Map<String, dynamic>.from(map)))
            .toList();
        
        // Sort by timestamp (newest first)
        bookmarks.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        
        // Update cache
        _bookmarksCache[audiobookId] = bookmarks;
        
        debugPrint('Loaded ${bookmarks.length} bookmarks for $audiobookId');
        return bookmarks;
      }
    } catch (e) {
      debugPrint('Error loading bookmarks for $audiobookId: $e');
    }
    
    // Return empty list if no bookmarks or error
    return [];
  }

  /// Deletes a bookmark
  Future<void> deleteBookmark(String audiobookId, String bookmarkId) async {
    try {
      final bookmarks = await getBookmarks(audiobookId);
      final updatedBookmarks = bookmarks.where((b) => b.id != bookmarkId).toList();
      
      final prefs = await _preferences;
      final key = '$bookmarksKey:$audiobookId';
      
      if (updatedBookmarks.isEmpty) {
        // Remove the entry completely if no bookmarks left
        await prefs.remove(key);
      } else {
        // Otherwise save the updated list
        final bookmarkMaps = updatedBookmarks.map((b) => b.toMap()).toList();
        await prefs.setString(key, jsonEncode(bookmarkMaps));
      }
      
      // Update cache
      _bookmarksCache[audiobookId] = updatedBookmarks;
      
      debugPrint('Deleted bookmark $bookmarkId from $audiobookId');
    } catch (e) {
      debugPrint('Error deleting bookmark: $e');
    }
  }

  /// Deletes all bookmarks for an audiobook
  Future<void> deleteAllBookmarks(String audiobookId) async {
    try {
      final prefs = await _preferences;
      final key = '$bookmarksKey:$audiobookId';
      await prefs.remove(key);
      
      // Update cache
      _bookmarksCache.remove(audiobookId);
      
      debugPrint('Deleted all bookmarks for $audiobookId');
    } catch (e) {
      debugPrint('Error deleting all bookmarks: $e');
    }
  }

  // Update this helper method to properly handle the cache
  Future<void> _saveCustomTitlesToPrefs() async {
    try {
      final prefs = await _preferences;
      
      // Convert map to a list of strings in format "id|title"
      final List<String> titlesList = [];
      _customTitlesCache.forEach((id, title) {
        titlesList.add("$id|$title");
      });

      await prefs.setStringList(customTitlesKey, titlesList);
      debugPrint("Saved ${titlesList.length} custom titles to preferences");
    } catch (e) {
      debugPrint("Error saving custom titles to preferences: $e");
    }
  }

  // Make sure to clean up the timer when the app is closed
  void dispose() {
    _cachePersistenceTimer?.cancel();
    _cachePersistenceTimer = null;
    
    // Force final persistence of any dirty caches
    _persistDirtyCaches();
  }

  /// Export all user data as a JSON file - COMPREHENSIVE BACKUP
  /// Captures: progress, positions, speeds, statistics, streaks, achievements, challenges, themes
  Future<File?> exportUserData() async {
    try {
      debugPrint('📦 Starting comprehensive backup export...');
      
      // First make sure we persist all caches
      await _persistDirtyCaches();
      
      final prefs = await _preferences;
      final allData = <String, dynamic>{
        'version': currentDataVersion,
        'timestamp': DateTime.now().toIso8601String(),
        'timestampMs': DateTime.now().millisecondsSinceEpoch,
        'backupType': 'comprehensive',
        'data': <String, dynamic>{},
      };
      
      // ===== 1. PROGRESS CACHE =====
      final progressData = <String, dynamic>{};
      for (final key in prefs.getKeys()) {
        if (key.startsWith(progressCachePrefix) && !key.endsWith(backupSuffix)) {
          final audiobookId = key.substring(progressCachePrefix.length);
          final value = prefs.getDouble(key);
          if (value != null) {
            progressData[audiobookId] = value;
          }
        }
      }
      allData['data']['progress'] = progressData;
      debugPrint('📦 Exported ${progressData.length} progress entries');
      
      // ===== 2. POSITION DATA =====
      final positionData = <String, dynamic>{};
      for (final key in prefs.getKeys()) {
        if (key.startsWith(lastPositionPrefix) && !key.endsWith(backupSuffix)) {
          final audiobookId = key.substring(lastPositionPrefix.length);
          final value = prefs.getString(key);
          if (value != null) {
            positionData[audiobookId] = value;
          }
        }
      }
      allData['data']['positions'] = positionData;
      debugPrint('📦 Exported ${positionData.length} position entries');
      
      // ===== 3. PLAYBACK SPEEDS (NEW) =====
      final speedData = <String, dynamic>{};
      for (final key in prefs.getKeys()) {
        if (key.startsWith('playback_speed_') && !key.endsWith(backupSuffix)) {
          final audiobookId = key.substring('playback_speed_'.length);
          final value = prefs.getDouble(key);
          if (value != null) {
            speedData[audiobookId] = value;
          }
        }
      }
      allData['data']['playback_speeds'] = speedData;
      debugPrint('📦 Exported ${speedData.length} playback speed entries');
      
      // ===== 4. BOOKMARKS =====
      final bookmarksData = <String, dynamic>{};
      for (final key in prefs.getKeys()) {
        if (key.startsWith('$bookmarksKey:') && !key.endsWith(backupSuffix)) {
          final audiobookId = key.substring('$bookmarksKey:'.length);
          final value = prefs.getString(key);
          if (value != null) {
            bookmarksData[audiobookId] = value;
          }
        }
      }
      allData['data']['bookmarks'] = bookmarksData;
      debugPrint('📦 Exported ${bookmarksData.length} bookmark sets');
      
      // ===== 5. COMPLETED BOOKS =====
      allData['data']['completed_books'] = prefs.getStringList(completedBooksKey) ?? [];
      
      // ===== 6. FOLDERS =====
      allData['data']['folders'] = prefs.getStringList(foldersKey) ?? [];
      
      // ===== 7. CUSTOM TITLES =====
      allData['data']['custom_titles'] = prefs.getStringList(customTitlesKey) ?? [];
      
      // ===== 8. TIMESTAMPS =====
      final timestampData = <String, dynamic>{};
      for (final key in prefs.getKeys()) {
        if (key.startsWith(lastPlayedTimestampPrefix) && !key.endsWith(backupSuffix)) {
          final audiobookId = key.substring(lastPlayedTimestampPrefix.length);
          final value = prefs.getInt(key);
          if (value != null) {
            timestampData[audiobookId] = value;
          }
        }
      }
      allData['data']['timestamps'] = timestampData;
      
      // ===== 9. TAGS =====
      final userTagsJson = prefs.getString(userTagsKey);
      if (userTagsJson != null) {
        allData['data']['user_tags'] = userTagsJson;
      }
      final audiobookTagsJson = prefs.getString(audiobookTagsKey);
      if (audiobookTagsJson != null) {
        allData['data']['audiobook_tags'] = audiobookTagsJson;
      }
      
      // ===== 10. REVIEWS (NEW) =====
      await loadAudiobookReviews();
      if (_reviewsCache.isNotEmpty) {
        allData['data']['reviews'] = jsonEncode(_reviewsCache);
        debugPrint('📦 Exported ${_reviewsCache.length} reviews');
      }
      
      // ===== 10. READING SESSIONS (NEW - Full Statistics) =====
      final sessionsData = <String, dynamic>{};
      for (final key in prefs.getKeys()) {
        if (key.startsWith('reading_session_') && !key.endsWith(backupSuffix)) {
          final value = prefs.getString(key);
          if (value != null) {
            sessionsData[key] = value;
          }
        }
      }
      allData['data']['reading_sessions'] = sessionsData;
      debugPrint('📦 Exported ${sessionsData.length} reading sessions');
      
      // ===== 11. DAILY STATS (NEW) =====
      final dailyStatsData = <String, dynamic>{};
      for (final key in prefs.getKeys()) {
        if (key.startsWith('daily_stats_') && !key.endsWith(backupSuffix)) {
          final value = prefs.getString(key);
          if (value != null) {
            dailyStatsData[key] = value;
          }
        }
      }
      allData['data']['daily_stats'] = dailyStatsData;
      debugPrint('📦 Exported ${dailyStatsData.length} daily stats');
      
      // ===== 12. STREAK DATA (NEW) =====
      final streakData = prefs.getString('reading_streak');
      if (streakData != null) {
        allData['data']['reading_streak'] = streakData;
      }
      
      // ===== 13. GOALS & SETTINGS (NEW) =====
      allData['data']['daily_reading_goal'] = prefs.getInt('daily_reading_goal');
      allData['data']['show_streak'] = prefs.getBool('show_streak');
      
      // ===== 14. ACHIEVEMENTS (NEW) =====
      final unlockedAchievements = prefs.getString('unlocked_achievements');
      if (unlockedAchievements != null) {
        allData['data']['unlocked_achievements'] = unlockedAchievements;
      }
      
      // ===== 15. CHALLENGES (NEW) =====
      final activeChallenges = prefs.getString('active_challenges');
      if (activeChallenges != null) {
        allData['data']['active_challenges'] = activeChallenges;
      }
      allData['data']['completed_challenges'] = prefs.getInt('completed_challenges');
      
      // ===== 16. THEME SETTINGS (NEW) =====
      allData['data']['theme_mode'] = prefs.getString('theme_mode');
      allData['data']['seed_color'] = prefs.getInt('seed_color');
      allData['data']['dynamic_theme'] = prefs.getBool('dynamic_theme');
      
      // ===== 17. VIEW PREFERENCES (NEW) =====
      allData['data']['is_grid_view'] = prefs.getBool('is_grid_view');
      allData['data']['library_sort_mode'] = prefs.getString('library_sort_mode');
      
      // ===== 18. CONTENT HASHES FOR PATH MIGRATION =====
      final contentHashes = prefs.getString('content_hashes');
      if (contentHashes != null) {
        allData['data']['content_hashes'] = contentHashes;
      }
      final pathMigrations = prefs.getString('path_migrations');
      if (pathMigrations != null) {
        allData['data']['path_migrations'] = pathMigrations;
      }
      
      // ===== 19. EQUALIZER & VOLUME BOOST (NEW) =====
      final eqData = <String, dynamic>{};
      for (final key in prefs.getKeys()) {
        if ((key.startsWith(_eqBookPrefix) || key.startsWith('eq_')) && !key.endsWith(backupSuffix)) {
          final value = prefs.get(key);
          if (value != null) {
            eqData[key] = value;
          }
        }
      }
      allData['data']['equalizer'] = eqData;
      debugPrint('📦 Exported ${eqData.length} equalizer settings');
      
      // Write to a file in the app's documents directory
      final dir = await getApplicationDocumentsDirectory();
      final now = DateTime.now().toIso8601String().replaceAll(':', '_');
      final file = File('${dir.path}/widdle_reader_backup_$now.json');
      
      final jsonString = jsonEncode(allData);
      await file.writeAsString(jsonString);
      
      debugPrint('📦 ✅ Comprehensive backup exported to ${file.path}');
      debugPrint('📦 Total backup size: ${(jsonString.length / 1024).toStringAsFixed(2)} KB');
      
      return file;
    } catch (e) {
      debugPrint('📦 ❌ Error exporting user data: $e');
      return null;
    }
  }
  
  /// Import user data from a JSON file - COMPREHENSIVE RESTORE
  Future<bool> importUserData(File file) async {
    try {
      debugPrint('📦 Starting comprehensive backup import...');
      
      // Read and parse the backup file
      final jsonString = await file.readAsString();
      final backupData = jsonDecode(jsonString) as Map<String, dynamic>;
      
      // Check version compatibility
      final version = backupData['version'] as int? ?? 0;
      if (version > currentDataVersion) {
        debugPrint('📦 Backup file version ($version) is newer than current version ($currentDataVersion)');
        return false;
      }
      
      // Create a backup of current data before importing
      await createDataBackup();
      
      final prefs = await _preferences;
      final data = backupData['data'] as Map<String, dynamic>;
      
      // ===== 1. PROGRESS CACHE =====
      final progressData = data['progress'] as Map<String, dynamic>? ?? {};
      for (final entry in progressData.entries) {
        final key = '$progressCachePrefix${entry.key}';
        await prefs.setDouble(key, double.parse(entry.value.toString()));
      }
      debugPrint('📦 Imported ${progressData.length} progress entries');
      
      // ===== 2. POSITION DATA =====
      final positionData = data['positions'] as Map<String, dynamic>? ?? {};
      for (final entry in positionData.entries) {
        if (entry.value != null) {
          final key = '$lastPositionPrefix${entry.key}';
          await prefs.setString(key, entry.value.toString());
        }
      }
      debugPrint('📦 Imported ${positionData.length} position entries');
      
      // ===== 3. PLAYBACK SPEEDS (NEW) =====
      final speedData = data['playback_speeds'] as Map<String, dynamic>? ?? {};
      for (final entry in speedData.entries) {
        if (entry.value != null) {
          await prefs.setDouble('playback_speed_${entry.key}', 
              double.tryParse(entry.value.toString()) ?? 1.0);
        }
      }
      debugPrint('📦 Imported ${speedData.length} playback speeds');
      
      // ===== 4. BOOKMARKS =====
      final bookmarksData = data['bookmarks'] as Map<String, dynamic>? ?? {};
      for (final entry in bookmarksData.entries) {
        final key = '$bookmarksKey:${entry.key}';
        await prefs.setString(key, entry.value.toString());
      }
      debugPrint('📦 Imported ${bookmarksData.length} bookmark sets');
      
      // ===== 5. COMPLETED BOOKS =====
      final completedBooks = (data['completed_books'] as List?)?.map((e) => e.toString()).toList() ?? [];
      await prefs.setStringList(completedBooksKey, completedBooks);
      
      // ===== 6. FOLDERS =====
      final folders = (data['folders'] as List?)?.map((e) => e.toString()).toList() ?? [];
      await prefs.setStringList(foldersKey, folders);
      
      // ===== 7. CUSTOM TITLES =====
      final customTitles = (data['custom_titles'] as List?)?.map((e) => e.toString()).toList() ?? [];
      await prefs.setStringList(customTitlesKey, customTitles);
      
      // ===== 8. TIMESTAMPS =====
      final timestampData = data['timestamps'] as Map<String, dynamic>? ?? {};
      for (final entry in timestampData.entries) {
        final key = '$lastPlayedTimestampPrefix${entry.key}';
        await prefs.setInt(key, int.parse(entry.value.toString()));
      }
      
      // ===== 9. TAGS =====
      final userTagsJson = data['user_tags'] as String?;
      if (userTagsJson != null) {
        await prefs.setString(userTagsKey, userTagsJson);
      }
      final audiobookTagsJson = data['audiobook_tags'] as String?;
      if (audiobookTagsJson != null) {
        await prefs.setString(audiobookTagsKey, audiobookTagsJson);
      }
      


      // ===== 10. REVIEWS (NEW) =====
      if (data['reviews'] != null) {
        final reviewsJson = data['reviews'] as String;
        await prefs.setString(reviewsKey, reviewsJson);
        // Force reload reviews cache
        _reviewsLoaded = false;
        await loadAudiobookReviews();
        debugPrint('📦 Imported reviews');
      }

      // ===== 11. READING SESSIONS (NEW) =====
      final sessionsData = data['reading_sessions'] as Map<String, dynamic>? ?? {};
      for (final entry in sessionsData.entries) {
        if (entry.value != null) {
          await prefs.setString(entry.key, entry.value.toString());
        }
      }
      debugPrint('📦 Imported ${sessionsData.length} reading sessions');
      
      // ===== 11. DAILY STATS (NEW) =====
      final dailyStatsData = data['daily_stats'] as Map<String, dynamic>? ?? {};
      for (final entry in dailyStatsData.entries) {
        if (entry.value != null) {
          await prefs.setString(entry.key, entry.value.toString());
        }
      }
      debugPrint('📦 Imported ${dailyStatsData.length} daily stats');
      
      // ===== 12. STREAK DATA (NEW) =====
      final streakData = data['reading_streak'] as String?;
      if (streakData != null) {
        await prefs.setString('reading_streak', streakData);
      }
      
      // ===== 13. GOALS & SETTINGS (NEW) =====
      if (data['daily_reading_goal'] != null) {
        await prefs.setInt('daily_reading_goal', data['daily_reading_goal'] as int);
      }
      if (data['show_streak'] != null) {
        await prefs.setBool('show_streak', data['show_streak'] as bool);
      }
      
      // ===== 14. ACHIEVEMENTS (NEW) =====
      final unlockedAchievements = data['unlocked_achievements'] as String?;
      if (unlockedAchievements != null) {
        await prefs.setString('unlocked_achievements', unlockedAchievements);
      }
      
      // ===== 15. CHALLENGES (NEW) =====
      final activeChallenges = data['active_challenges'] as String?;
      if (activeChallenges != null) {
        await prefs.setString('active_challenges', activeChallenges);
      }
      if (data['completed_challenges'] != null) {
        await prefs.setInt('completed_challenges', data['completed_challenges'] as int);
      }
      
      // ===== 16. THEME SETTINGS (NEW) =====
      if (data['theme_mode'] != null) {
        await prefs.setString('theme_mode', data['theme_mode'].toString());
      }
      if (data['seed_color'] != null) {
        await prefs.setInt('seed_color', data['seed_color'] as int);
      }
      if (data['dynamic_theme'] != null) {
        await prefs.setBool('dynamic_theme', data['dynamic_theme'] as bool);
      }
      
      // ===== 17. VIEW PREFERENCES (NEW) =====
      if (data['is_grid_view'] != null) {
        await prefs.setBool('is_grid_view', data['is_grid_view'] as bool);
      }
      if (data['library_sort_mode'] != null) {
        await prefs.setString('library_sort_mode', data['library_sort_mode'].toString());
      }
      
      // ===== 18. CONTENT HASHES (NEW) =====
      if (data['content_hashes'] != null) {
        await prefs.setString('content_hashes', data['content_hashes'].toString());
      }
      if (data['path_migrations'] != null) {
        await prefs.setString('path_migrations', data['path_migrations'].toString());
      }
      
      // ===== 19. EQUALIZER & VOLUME BOOST (NEW) =====
      if (data['equalizer'] != null) {
        final eqData = data['equalizer'] as Map<String, dynamic>;
        for (final entry in eqData.entries) {
          final key = entry.key;
          final value = entry.value;
          if (value is bool) {
            await prefs.setBool(key, value);
          } else if (value is double) {
            await prefs.setDouble(key, value);
          } else if (value is int) {
            await prefs.setInt(key, value);
          } else if (value is String) {
            await prefs.setString(key, value);
          }
        }
        debugPrint('📦 Imported ${eqData.length} equalizer settings');
      }
      
      // Clear all caches to force reload from imported data
      _progressCache.clear();
      _positionCache.clear();
      _timestampCache.clear();
      _completedBooksCache.clear();
      _customTitlesCache.clear();
      _foldersCache.clear();
      _playbackSpeedCache.clear();
      _eqSettingsCache.clear();
      
      // Clear all dirty flags
      _dirtyProgressCache.clear();
      _dirtyPositionCache.clear();
      _dirtyTimestampCache.clear();
      _dirtyCompletedBooksCache = false;
      _dirtyCustomTitlesCache = false;
      _dirtyFoldersCache = false;
      
      // Notify providers to refresh their data
      _notifyRestoreListeners();
      
      debugPrint('📦 ✅ Comprehensive backup imported successfully');
      return true;
    } catch (e) {
      debugPrint('📦 ❌ Error importing user data: $e');
      return false;
    }
  }

  /// ========================================
  /// PERFORMANCE OPTIMIZATION - CACHING
  /// ========================================

  /// Cache basic audiobook info (lightweight data for initial load)
  Future<void> cacheBasicBookInfo(String audiobookId, Map<String, dynamic> basicInfo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'basic_book_info_$audiobookId';
      await prefs.setString(key, jsonEncode(basicInfo));
    } catch (e) {
      debugPrint("Error caching basic book info for $audiobookId: $e");
    }
  }

  /// Load cached basic book info
  Future<Map<String, dynamic>?> loadCachedBasicBookInfo(String audiobookId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'basic_book_info_$audiobookId';
      final cached = prefs.getString(key);
      if (cached != null) {
        return Map<String, dynamic>.from(jsonDecode(cached));
      }
    } catch (e) {
      debugPrint("Error loading cached basic book info for $audiobookId: $e");
    }
    return null;
  }

  /// Cache detailed metadata (heavy data loaded on-demand)
  Future<void> cacheDetailedMetadata(String audiobookId, Map<String, dynamic> metadata) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'detailed_metadata_$audiobookId';
      await prefs.setString(key, jsonEncode(metadata));
    } catch (e) {
      debugPrint("Error caching detailed metadata for $audiobookId: $e");
    }
  }

  /// Load cached detailed metadata
  Future<Map<String, dynamic>?> loadCachedDetailedMetadata(String audiobookId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'detailed_metadata_$audiobookId';
      final cached = prefs.getString(key);
      if (cached != null) {
        return Map<String, dynamic>.from(jsonDecode(cached));
      }
    } catch (e) {
      debugPrint("Error loading cached detailed metadata for $audiobookId: $e");
    }
    return null;
  }

  /// Cache cover art separately (can be large)
  Future<void> cacheCoverArt(String audiobookId, Uint8List coverArt) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/cover_${audiobookId.hashCode}.jpg');
      await file.writeAsBytes(coverArt);
    } catch (e) {
      debugPrint("Error caching cover art for $audiobookId: $e");
    }
  }

  /// Get the file path for cached cover art
  Future<String?> getCachedCoverArtPath(String audiobookId) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/cover_${audiobookId.hashCode}.jpg');
      if (await file.exists()) {
        return file.path;
      }
    } catch (e) {
      debugPrint("Error getting cached cover art path for $audiobookId: $e");
    }
    return null;
  }

  /// Load cached cover art
  Future<Uint8List?> loadCachedCoverArt(String audiobookId) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/cover_${audiobookId.hashCode}.jpg');
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (e) {
      debugPrint("Error loading cached cover art for $audiobookId: $e");
    }
    return null;
  }

  /// Clear all metadata cache (for debugging or storage cleanup)
  Future<void> clearMetadataCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) => 
        key.startsWith('basic_book_info_') || 
        key.startsWith('detailed_metadata_')
      ).toList();
      
      for (final key in keys) {
        await prefs.remove(key);
      }

      // Clear cover art cache
      final directory = await getApplicationDocumentsDirectory();
      final files = await directory.list().where((entity) => 
        entity is File && entity.path.contains('cover_')
      ).toList();
      
      for (final file in files) {
        try {
          await file.delete();
        } catch (e) {
          debugPrint("Error deleting cached cover art: $e");
        }
      }
      
      debugPrint("Metadata cache cleared");
    } catch (e) {
      debugPrint("Error clearing metadata cache: $e");
    }
  }

  /// Check if basic book info is cached and up-to-date
  Future<bool> isBasicBookInfoCached(String audiobookId, String folderPath) async {
    try {
      final cached = await loadCachedBasicBookInfo(audiobookId);
      if (cached == null) return false;

      // Check if folder still exists and hasn't been modified
      final directory = Directory(folderPath);
      if (!await directory.exists()) return false;

      final stat = await directory.stat();
      final cachedModified = cached['folderModified'] as int?;
      
      return cachedModified == stat.modified.millisecondsSinceEpoch;
    } catch (e) {
      debugPrint("Error checking cache validity for $audiobookId: $e");
      return false;
    }
  }

  /// Removes all data associated with an audiobook when it's deleted
  Future<void> removeAudiobookData(String audiobookId) async {
    try {
      final prefs = await _preferences;
      
      // Remove progress data
      final progressKey = '$progressCachePrefix$audiobookId';
      await prefs.remove(progressKey);
      _progressCache.remove(audiobookId);
      _dirtyProgressCache.remove(audiobookId);
      
      // Remove position data
      final positionKey = '$lastPositionPrefix$audiobookId';
      await prefs.remove(positionKey);
      _positionCache.remove(audiobookId);
      _dirtyPositionCache.remove(audiobookId);
      
      // Remove bookmarks
      final bookmarksKey = '$bookmarksPrefix$audiobookId';
      await prefs.remove(bookmarksKey);
      
      // Remove timestamp data
      final timestampKey = '$lastPlayedTimestampPrefix$audiobookId';
      await prefs.remove(timestampKey);
      _timestampCache.remove(audiobookId);
      _dirtyTimestampCache.remove(audiobookId);
      
      // Remove playback speed data
      final playbackSpeedKey = '$playbackSpeedPrefix$audiobookId';
      await prefs.remove(playbackSpeedKey);
      _playbackSpeedCache.remove(audiobookId);
      _dirtyPlaybackSpeedCache.remove(audiobookId);
      
      // Remove from completed books
      await removeFromCompleted(audiobookId);
      
      // Remove basic and detailed cache data
      await prefs.remove('basic_book_info_$audiobookId');
      await prefs.remove('detailed_metadata_$audiobookId');
      
      // Remove review
      await loadAudiobookReviews();
      if (_reviewsCache.containsKey(audiobookId)) {
        _reviewsCache.remove(audiobookId);
        await prefs.setString(reviewsKey, jsonEncode(_reviewsCache));
      }
      
      // Remove cached cover art
      try {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/cover_${audiobookId.hashCode}.jpg');
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint("Error removing cached cover art for $audiobookId: $e");
      }
      
      // Update folder list to remove this audiobook
      final folders = await loadAudiobookFolders();
      final updatedFolders = folders.where((folder) => folder != audiobookId).toList();
      await saveAudiobookFolders(updatedFolders);
      
      debugPrint("Successfully removed all data for audiobook: $audiobookId");
    } catch (e) {
      debugPrint("Error removing audiobook data for $audiobookId: $e");
      rethrow;
    }
  }

  /// Updates all stored references to an audiobook when its ID changes
  Future<void> updateAudiobookId(String oldId, String newId) async {
    try {
      final prefs = await _preferences;
      
      // Update progress data
      final oldProgressKey = '$progressCachePrefix$oldId';
      final newProgressKey = '$progressCachePrefix$newId';
      final progressValue = prefs.getDouble(oldProgressKey);
      if (progressValue != null) {
        await prefs.setDouble(newProgressKey, progressValue);
        await prefs.remove(oldProgressKey);
        _progressCache[newId] = _progressCache.remove(oldId) ?? 0.0;
        if (_dirtyProgressCache.remove(oldId)) {
          _dirtyProgressCache.add(newId);
        }
      }
      
      // Update position data
      final oldPositionKey = '$lastPositionPrefix$oldId';
      final newPositionKey = '$lastPositionPrefix$newId';
      final positionValue = prefs.getInt(oldPositionKey);
      if (positionValue != null) {
        await prefs.setInt(newPositionKey, positionValue);
        await prefs.remove(oldPositionKey);
        _positionCache[newId] = _positionCache.remove(oldId) ?? {};
        if (_dirtyPositionCache.remove(oldId)) {
          _dirtyPositionCache.add(newId);
        }
      }
      
      // Update bookmarks
      final oldBookmarksKey = '$bookmarksPrefix$oldId';
      final newBookmarksKey = '$bookmarksPrefix$newId';
      final bookmarksValue = prefs.getString(oldBookmarksKey);
      if (bookmarksValue != null) {
        await prefs.setString(newBookmarksKey, bookmarksValue);
        await prefs.remove(oldBookmarksKey);
      }
      
      // Update reviews
      await loadAudiobookReviews();
      if (_reviewsCache.containsKey(oldId)) {
        _reviewsCache[newId] = _reviewsCache.remove(oldId)!;
        await prefs.setString(reviewsKey, jsonEncode(_reviewsCache));
      }
      
      // Update timestamp data
      final oldTimestampKey = '$lastPlayedTimestampPrefix$oldId';
      final newTimestampKey = '$lastPlayedTimestampPrefix$newId';
      final timestampValue = prefs.getInt(oldTimestampKey);
      if (timestampValue != null) {
        await prefs.setInt(newTimestampKey, timestampValue);
        await prefs.remove(oldTimestampKey);
        _timestampCache[newId] = _timestampCache.remove(oldId) ?? 0;
        if (_dirtyTimestampCache.remove(oldId)) {
          _dirtyTimestampCache.add(newId);
        }
      }
      
      // Update playback speed data
      final oldPlaybackSpeedKey = '$playbackSpeedPrefix$oldId';
      final newPlaybackSpeedKey = '$playbackSpeedPrefix$newId';
      final playbackSpeedValue = prefs.getDouble(oldPlaybackSpeedKey);
      if (playbackSpeedValue != null) {
        await prefs.setDouble(newPlaybackSpeedKey, playbackSpeedValue);
        await prefs.remove(oldPlaybackSpeedKey);
        _playbackSpeedCache[newId] = _playbackSpeedCache.remove(oldId) ?? 1.0;
        if (_dirtyPlaybackSpeedCache.remove(oldId)) {
          _dirtyPlaybackSpeedCache.add(newId);
        }
      }
      
      // Update completed books list
      if (_completedBooksCache.contains(oldId)) {
        _completedBooksCache.remove(oldId);
        _completedBooksCache.add(newId);
        _dirtyCompletedBooksCache = true;
        await _saveCompletedBooksCache();
      }
      
      // Update basic and detailed cache data
      final basicInfo = prefs.getString('basic_book_info_$oldId');
      if (basicInfo != null) {
        await prefs.setString('basic_book_info_$newId', basicInfo);
        await prefs.remove('basic_book_info_$oldId');
      }
      
      final detailedInfo = prefs.getString('detailed_metadata_$oldId');
      if (detailedInfo != null) {
        await prefs.setString('detailed_metadata_$newId', detailedInfo);
        await prefs.remove('detailed_metadata_$oldId');
      }
      
      // Update cached cover art
      try {
        final directory = await getApplicationDocumentsDirectory();
        final oldFile = File('${directory.path}/cover_${oldId.hashCode}.jpg');
        final newFile = File('${directory.path}/cover_${newId.hashCode}.jpg');
        
        if (await oldFile.exists()) {
          await oldFile.copy(newFile.path);
          await oldFile.delete();
        }
      } catch (e) {
        debugPrint("Error updating cached cover art for $oldId -> $newId: $e");
      }
      
      // Update folder list
      final folders = await loadAudiobookFolders();
      final folderIndex = folders.indexOf(oldId);
      if (folderIndex != -1) {
        folders[folderIndex] = newId;
        await saveAudiobookFolders(folders);
      }
      
      debugPrint("Successfully updated audiobook ID: $oldId -> $newId");
    } catch (e) {
      debugPrint("Error updating audiobook ID from $oldId to $newId: $e");
      rethrow;
    }
  }

  /// Removes an audiobook from the completed books list
  Future<void> removeFromCompleted(String audiobookId) async {
    try {
      if (_completedBooksCache.contains(audiobookId)) {
        _completedBooksCache.remove(audiobookId);
        _dirtyCompletedBooksCache = true;
        await _saveCompletedBooksCache();
        debugPrint("Removed $audiobookId from completed books");
      }
    } catch (e) {
      debugPrint("Error removing $audiobookId from completed books: $e");
    }
  }

  /// Saves the completed books cache to SharedPreferences
  Future<void> _saveCompletedBooksCache() async {
    try {
      final prefs = await _preferences;
      await prefs.setStringList(completedBooksKey, _completedBooksCache.toList());
      _dirtyCompletedBooksCache = false;
      debugPrint("Saved completed books cache: ${_completedBooksCache.length} items");
    } catch (e) {
      debugPrint("Error saving completed books cache: $e");
    }
  }

  /// Finds a migrated path for an audiobook using the file tracking system
  Future<String?> findMigratedPath(String oldPath) async {
    try {
      // Load path migrations cache if not already loaded
      if (_pathMigrationsCache.isEmpty) {
        final prefs = await _preferences;
        final migrationsJson = prefs.getString(pathMigrationsKey);
        if (migrationsJson != null) {
          final Map<String, dynamic> migrationsData = jsonDecode(migrationsJson);
          _pathMigrationsCache = Map<String, String>.from(migrationsData);
        }
      }

      // Check direct path migration mapping
      if (_pathMigrationsCache.containsKey(oldPath)) {
        final newPath = _pathMigrationsCache[oldPath]!;
        if (await Directory(newPath).exists()) {
          return newPath;
        }
      }

      // Try to find using content hash (more comprehensive search)
      final contentHash = await generateContentHash(oldPath);
      if (contentHash.isNotEmpty) {
        // Load content hashes cache
        if (_contentHashesCache.isEmpty) {
          final prefs = await _preferences;
          final hashesJson = prefs.getString(contentHashesKey);
          if (hashesJson != null) {
            final Map<String, dynamic> hashesData = jsonDecode(hashesJson);
            _contentHashesCache = Map<String, String>.from(hashesData);
          }
        }

        // Check if this content hash maps to a current path
        if (_contentHashesCache.containsKey(contentHash)) {
          final currentPath = _contentHashesCache[contentHash]!;
          if (await Directory(currentPath).exists() && currentPath != oldPath) {
            // Found a match - update path migration mapping
            _pathMigrationsCache[oldPath] = currentPath;
            _dirtyPathMigrationsCache = true;
            return currentPath;
          }
        }
      }

      return null; // No migration path found
    } catch (e) {
      debugPrint("Error finding migrated path for $oldPath: $e");
      return null;
    }
  }

  /// Loads a stored content hash for an audiobook path
  Future<String?> loadStoredContentHash(String audiobookPath) async {
    try {
      // Load content hashes cache if not already loaded
      if (_contentHashesCache.isEmpty) {
        final prefs = await _preferences;
        final hashesJson = prefs.getString(contentHashesKey);
        if (hashesJson != null) {
          final Map<String, dynamic> hashesData = jsonDecode(hashesJson);
          _contentHashesCache = Map<String, String>.from(hashesData);
        }
      }

      // Find the hash for this path
      for (final entry in _contentHashesCache.entries) {
        if (entry.value == audiobookPath) {
          return entry.key; // Return the hash
        }
      }

      return null;
    } catch (e) {
      debugPrint("Error loading stored content hash for $audiobookPath: $e");
      return null;
    }
  }

  /// Updates the content hash mapping for an audiobook
  Future<void> updateContentHash(String contentHash, String currentPath) async {
    try {
      if (contentHash.isEmpty) return;

      // Load content hashes cache if not already loaded
      if (_contentHashesCache.isEmpty) {
        final prefs = await _preferences;
        final hashesJson = prefs.getString(contentHashesKey);
        if (hashesJson != null) {
          final Map<String, dynamic> hashesData = jsonDecode(hashesJson);
          _contentHashesCache = Map<String, String>.from(hashesData);
        }
      }

      // Update the mapping
      _contentHashesCache[contentHash] = currentPath;
      _dirtyContentHashesCache = true;

      // Immediately persist this important change
      final prefs = await _preferences;
      await prefs.setString(contentHashesKey, jsonEncode(_contentHashesCache));
      _dirtyContentHashesCache = false;

      debugPrint("Updated content hash mapping: $contentHash -> $currentPath");
    } catch (e) {
      debugPrint("Error updating content hash for $currentPath: $e");
    }
  }

  Future<double?> getPlaybackSpeed(String audiobookId) async {
    if (!_playbackSpeedLoaded) {
      final prefs = await _preferences;
      for (final key in prefs.getKeys()) {
        if (key.startsWith(playbackSpeedPrefix)) {
          final value = prefs.getDouble(key);
          if (value != null) {
            _playbackSpeedCache[key.substring(playbackSpeedPrefix.length)] = value;
          }
        }
      }
      _playbackSpeedLoaded = true;
    }

    return _playbackSpeedCache[audiobookId];
  }

  Future<void> savePlaybackSpeed(String audiobookId, double speed) async {
    _playbackSpeedCache[audiobookId] = speed;
    _dirtyPlaybackSpeedCache.add(audiobookId);
    await _markCacheForPersistence();
  }

  Future<void> _markCacheForPersistence() async {
    // No-op placeholder to maintain compatibility with existing call sites that
    // expect an async method when marking cache entries dirty. All persistence
    // happens in _persistDirtyCaches().
  }

  void resetCacheForImportOnly() {
    _progressCache.clear();
    _positionCache.clear();
    _timestampCache.clear();
    _completedBooksCache.clear();
    _customTitlesCache = {};
    _playbackSpeedCache.clear();
    _playbackSpeedLoaded = false;
  }
}
