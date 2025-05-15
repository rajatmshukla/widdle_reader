import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:path/path.dart';
import 'dart:io';
import 'dart:convert'; // Add this import for JSON encoding/decoding
import 'package:path_provider/path_provider.dart';
import '../models/bookmark.dart'; // Import the Bookmark model

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

  // Singleton instance for this service 
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  // Cached SharedPreferences instance
  SharedPreferences? _prefs;
  
  // In-memory caches to reduce disk access
  final Map<String, double> _progressCache = {};
  final Map<String, Map<String, dynamic>> _positionCache = {};
  final Map<String, int> _timestampCache = {};
  final Set<String> _completedBooksCache = {};
  Map<String, String> _customTitlesCache = {};
  List<String> _foldersCache = [];
  
  // Initialization method to ensure the SharedPreferences instance exists
  Future<SharedPreferences> get _preferences async {
    if (_prefs == null) {
      _prefs = await SharedPreferences.getInstance();
      
      // Load initial caches
      _completedBooksCache.addAll(_prefs!.getStringList(completedBooksKey) ?? []);
      _foldersCache = _prefs!.getStringList(foldersKey) ?? [];
      
      // Load custom titles
      await loadCustomTitles();
    }
    return _prefs!;
  }

  /// Saves a list of audiobook folder paths to shared preferences
  Future<void> saveAudiobookFolders(List<String> paths) async {
    try {
      final prefs = await _preferences;
      await prefs.setStringList(foldersKey, paths);
      
      // Update cache
      _foldersCache = paths;
      
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
      final prefs = await _preferences;
      final key = '$lastPositionPrefix$audiobookId';
      // Store as "chapterId|milliseconds"
      final value = '$chapterId|${position.inMilliseconds}';
      await prefs.setString(key, value);

      // Update position cache
      _positionCache[audiobookId] = {
        'chapterId': chapterId,
        'position': position
      };

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
      final prefs = await _preferences;
      final key = '$lastPlayedTimestampPrefix$audiobookId';
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(key, now);
      
      // Update cache
      _timestampCache[audiobookId] = now;
      
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
      
      final prefs = await _preferences;
      final completedBooks = prefs.getStringList(completedBooksKey) ?? [];

      if (!completedBooks.contains(audiobookId)) {
        completedBooks.add(audiobookId);
        await prefs.setStringList(completedBooksKey, completedBooks);
        
        // Update cache
        _completedBooksCache.add(audiobookId);
        
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
      final prefs = await _preferences;

      // Convert map to a list of strings in format "id|title"
      final List<String> titlesList = [];
      customTitles.forEach((id, title) {
        titlesList.add("$id|$title");
      });

      await prefs.setStringList(customTitlesKey, titlesList);
      
      // Update cache
      _customTitlesCache = Map.from(customTitles);
      
      debugPrint("Saved ${titlesList.length} custom titles");
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
      final prefs = await _preferences;
      final key = '$progressCachePrefix$audiobookId';
      await prefs.setDouble(key, progressPercentage);
      
      // Update in-memory cache
      _progressCache[audiobookId] = progressPercentage;
      
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
}
