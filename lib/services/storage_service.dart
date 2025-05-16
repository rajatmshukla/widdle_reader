import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:path/path.dart';
import 'dart:io';
import 'dart:convert'; // Add this import for JSON encoding/decoding
import 'package:path_provider/path_provider.dart';
import '../models/bookmark.dart'; // Import the Bookmark model
import 'dart:async'; // For periodic cache persistence

class StorageService {
  // Key constants for SharedPreferences
  static const foldersKey = 'audiobook_folders';
  static const lastPositionPrefix = 'last_pos_';
  static const customTitlesKey = 'custom_titles';
  static const progressCachePrefix = 'progress_cache_';
  static const lastPlayedTimestampPrefix =
      'last_played_'; // New key for timestamps
  static const completionPrefix = 'completion_';
  static const completedBooksKey =
      'completed_books'; // New key for completed books
  static const bookmarksKey = 'bookmarks'; // New key for bookmarks
  static const backupSuffix = '_backup';
  static const dataVersionKey = 'data_version';
  static const cacheSyncTimestampKey = 'cache_sync_timestamp';

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
  List<String> _foldersCache = [];
  
  // Cache dirty flags to track which caches need persisting
  final Set<String> _dirtyProgressCache = {};
  final Set<String> _dirtyPositionCache = {};
  final Set<String> _dirtyTimestampCache = {};
  bool _dirtyCompletedBooksCache = false;
  bool _dirtyCustomTitlesCache = false;
  bool _dirtyFoldersCache = false;

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
          if (value != null && !prefs.containsKey(originalKey)) {
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
          if (value != null && !prefs.containsKey(originalKey)) {
            await prefs.setString(originalKey, value);
            restoredAnyData = true;
          }
        }
      }
      
      // Restore completed books
      final completedBooksBackup = prefs.getStringList('$completedBooksKey$backupSuffix');
      if (completedBooksBackup != null && !prefs.containsKey(completedBooksKey)) {
        await prefs.setStringList(completedBooksKey, completedBooksBackup);
        restoredAnyData = true;
      }
      
      // Restore custom titles
      final customTitlesBackup = prefs.getStringList('$customTitlesKey$backupSuffix');
      if (customTitlesBackup != null && !prefs.containsKey(customTitlesKey)) {
        await prefs.setStringList(customTitlesKey, customTitlesBackup);
        restoredAnyData = true;
      }
      
      // Restore folders
      final foldersBackup = prefs.getStringList('$foldersKey$backupSuffix');
      if (foldersBackup != null && !prefs.containsKey(foldersKey)) {
        await prefs.setStringList(foldersKey, foldersBackup);
        restoredAnyData = true;
      }
      
      // Restore bookmarks
      for (final key in prefs.getKeys()) {
        if (key.endsWith(backupSuffix) && key.startsWith('$bookmarksKey:')) {
          final originalKey = key.substring(0, key.length - backupSuffix.length);
          final value = prefs.getString(key);
          if (value != null && !prefs.containsKey(originalKey)) {
            await prefs.setString(originalKey, value);
            restoredAnyData = true;
          }
        }
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
        if (key.startsWith('$bookmarksKey:')) bookmarkCount++;
      }
      
      completedBooksCount = (prefs.getStringList(completedBooksKey) ?? []).length;
      final foldersCount = (prefs.getStringList(foldersKey) ?? []).length;
      final customTitlesCount = (prefs.getStringList(customTitlesKey) ?? []).length;
      
      result['counts'] = {
        'progress': progressCount,
        'positions': positionCount,
        'bookmarks': bookmarkCount,
        'completedBooks': completedBooksCount,
        'folders': foldersCount,
        'customTitles': customTitlesCount,
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

  /// Loads list of audiobook folder paths from shared preferences
  Future<List<String>> loadAudiobookFolders() async {
    try {
      // Check cache first
      if (_foldersCache.isNotEmpty) {
        return _foldersCache;
      }
      
      final prefs = await _preferences;
      final folders = prefs.getStringList(foldersKey) ?? [];
      
      // Update cache
      _foldersCache = folders;
      _dirtyFoldersCache = false;
      
      debugPrint("Loaded audiobook folders: $folders");
      return folders;
    } catch (e) {
      debugPrint("Error loading audiobook folders: $e");
      return []; // Return empty list on error
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

  /// Saves custom titles for audiobooks
  Future<void> saveCustomTitles(Map<String, String> customTitles) async {
    try {
      // Update cache
      _customTitlesCache = Map.from(customTitles);
      _dirtyCustomTitlesCache = true;
      
      // Save to preferences
      await _saveCustomTitlesToPrefs();
      
      debugPrint("Saved ${customTitles.length} custom titles");
    } catch (e) {
      debugPrint("Error saving custom titles: $e");
    }
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

  /// Export all user data as a JSON file
  Future<File?> exportUserData() async {
    try {
      debugPrint('Exporting user data to backup file...');
      
      // First make sure we persist all caches
      await _persistDirtyCaches();
      
      final prefs = await _preferences;
      final allData = <String, dynamic>{
        'version': currentDataVersion,
        'timestamp': DateTime.now().toIso8601String(),
        'data': <String, dynamic>{},
      };
      
      // Export progress cache
      final progressData = <String, dynamic>{};
      for (final key in prefs.getKeys()) {
        if (key.startsWith(progressCachePrefix)) {
          final audiobookId = key.substring(progressCachePrefix.length);
          progressData[audiobookId] = prefs.getDouble(key);
        }
      }
      allData['data']['progress'] = progressData;
      
      // Export position data
      final positionData = <String, dynamic>{};
      for (final key in prefs.getKeys()) {
        if (key.startsWith(lastPositionPrefix)) {
          final audiobookId = key.substring(lastPositionPrefix.length);
          positionData[audiobookId] = prefs.getString(key);
        }
      }
      allData['data']['positions'] = positionData;
      
      // Export bookmarks
      final bookmarksData = <String, dynamic>{};
      for (final key in prefs.getKeys()) {
        if (key.startsWith('$bookmarksKey:')) {
          final audiobookId = key.substring('$bookmarksKey:'.length);
          bookmarksData[audiobookId] = prefs.getString(key);
        }
      }
      allData['data']['bookmarks'] = bookmarksData;
      
      // Export completed books
      allData['data']['completed_books'] = prefs.getStringList(completedBooksKey) ?? [];
      
      // Export folders
      allData['data']['folders'] = prefs.getStringList(foldersKey) ?? [];
      
      // Export custom titles
      allData['data']['custom_titles'] = prefs.getStringList(customTitlesKey) ?? [];
      
      // Export timestamps
      final timestampData = <String, dynamic>{};
      for (final key in prefs.getKeys()) {
        if (key.startsWith(lastPlayedTimestampPrefix)) {
          final audiobookId = key.substring(lastPlayedTimestampPrefix.length);
          timestampData[audiobookId] = prefs.getInt(key);
        }
      }
      allData['data']['timestamps'] = timestampData;
      
      // Write to a file in the app's documents directory
      final dir = await getApplicationDocumentsDirectory();
      final now = DateTime.now().toIso8601String().replaceAll(':', '_');
      final file = File('${dir.path}/widdle_reader_backup_$now.json');
      
      await file.writeAsString(jsonEncode(allData));
      debugPrint('User data exported successfully to ${file.path}');
      
      return file;
    } catch (e) {
      debugPrint('Error exporting user data: $e');
      return null;
    }
  }
  
  /// Import user data from a JSON file
  Future<bool> importUserData(File file) async {
    try {
      debugPrint('Importing user data from backup file...');
      
      // Read and parse the backup file
      final jsonString = await file.readAsString();
      final backupData = jsonDecode(jsonString) as Map<String, dynamic>;
      
      // Check version compatibility
      final version = backupData['version'] as int? ?? 0;
      if (version > currentDataVersion) {
        debugPrint('Backup file version ($version) is newer than current version ($currentDataVersion)');
        return false;
      }
      
      // Create a backup of current data before importing
      await createDataBackup();
      
      final prefs = await _preferences;
      final data = backupData['data'] as Map<String, dynamic>;
      
      // Import progress cache
      final progressData = data['progress'] as Map<String, dynamic>? ?? {};
      for (final entry in progressData.entries) {
        final key = '$progressCachePrefix${entry.key}';
        await prefs.setDouble(key, double.parse(entry.value.toString()));
      }
      
      // Import position data
      final positionData = data['positions'] as Map<String, dynamic>? ?? {};
      for (final entry in positionData.entries) {
        final key = '$lastPositionPrefix${entry.key}';
        await prefs.setString(key, entry.value.toString());
      }
      
      // Import bookmarks
      final bookmarksData = data['bookmarks'] as Map<String, dynamic>? ?? {};
      for (final entry in bookmarksData.entries) {
        final key = '$bookmarksKey:${entry.key}';
        await prefs.setString(key, entry.value.toString());
      }
      
      // Import completed books
      final completedBooks = (data['completed_books'] as List?)?.map((e) => e.toString()).toList() ?? [];
      await prefs.setStringList(completedBooksKey, completedBooks);
      
      // Import folders
      final folders = (data['folders'] as List?)?.map((e) => e.toString()).toList() ?? [];
      await prefs.setStringList(foldersKey, folders);
      
      // Import custom titles
      final customTitles = (data['custom_titles'] as List?)?.map((e) => e.toString()).toList() ?? [];
      await prefs.setStringList(customTitlesKey, customTitles);
      
      // Import timestamps
      final timestampData = data['timestamps'] as Map<String, dynamic>? ?? {};
      for (final entry in timestampData.entries) {
        final key = '$lastPlayedTimestampPrefix${entry.key}';
        await prefs.setInt(key, int.parse(entry.value.toString()));
      }
      
      // Clear all caches to force reload from imported data
      _progressCache.clear();
      _positionCache.clear();
      _timestampCache.clear();
      _completedBooksCache.clear();
      _customTitlesCache.clear();
      _foldersCache.clear();
      
      // Clear all dirty flags
      _dirtyProgressCache.clear();
      _dirtyPositionCache.clear();
      _dirtyTimestampCache.clear();
      _dirtyCompletedBooksCache = false;
      _dirtyCustomTitlesCache = false;
      _dirtyFoldersCache = false;
      
      debugPrint('User data imported successfully');
      return true;
    } catch (e) {
      debugPrint('Error importing user data: $e');
      return false;
    }
  }
}
