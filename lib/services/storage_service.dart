import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'; // For debugPrint

class StorageService {
  // Key constants for SharedPreferences
  static const _foldersKey = 'audiobook_folders';
  static const _lastPositionPrefix = 'last_pos_';
  static const _customTitlesKey = 'custom_titles';
  static const _progressCachePrefix = 'progress_cache_';

  /// Saves a list of audiobook folder paths to shared preferences
  Future<void> saveAudiobookFolders(List<String> paths) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_foldersKey, paths);
      debugPrint("Saved audiobook folders: $paths");
    } catch (e) {
      debugPrint("Error saving audiobook folders: $e");
    }
  }

  /// Loads list of audiobook folder paths from shared preferences
  Future<List<String>> loadAudiobookFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final folders = prefs.getStringList(_foldersKey) ?? [];
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
      final prefs = await SharedPreferences.getInstance();
      final key = '$_lastPositionPrefix$audiobookId';
      // Store as "chapterId|milliseconds"
      final value = '$chapterId|${position.inMilliseconds}';
      await prefs.setString(key, value);

      // Clear any cached progress percentage to force recalculation
      await _clearProgressCache(audiobookId);

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
      final prefs = await SharedPreferences.getInstance();
      final key = '$_lastPositionPrefix$audiobookId';
      final savedData = prefs.getString(key);

      if (savedData != null) {
        final parts = savedData.split('|');
        // Ensure data format is correct (chapterId|milliseconds)
        if (parts.length == 2) {
          final chapterId = parts[0];
          final positionMillis = int.tryParse(parts[1]);

          if (positionMillis != null && chapterId.isNotEmpty) {
            final position = Duration(milliseconds: positionMillis);
            debugPrint(
              'Loaded position for $audiobookId: $chapterId at ${position.inMilliseconds}ms',
            );
            return {'chapterId': chapterId, 'position': position};
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

  /// Clears the saved playback position for a specific audiobook.
  Future<void> clearLastPosition(String audiobookId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_lastPositionPrefix$audiobookId';
      await prefs.remove(key);

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
      final prefs = await SharedPreferences.getInstance();

      // Convert map to a list of strings in format "id|title"
      final List<String> titlesList = [];
      customTitles.forEach((id, title) {
        titlesList.add("$id|$title");
      });

      await prefs.setStringList(_customTitlesKey, titlesList);
      debugPrint("Saved ${titlesList.length} custom titles");
    } catch (e) {
      debugPrint("Error saving custom titles: $e");
    }
  }

  /// Loads custom titles for audiobooks
  Future<Map<String, String>> loadCustomTitles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final titlesList = prefs.getStringList(_customTitlesKey) ?? [];

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
      final prefs = await SharedPreferences.getInstance();
      final key = '$_progressCachePrefix$audiobookId';
      await prefs.setDouble(key, progressPercentage);
      debugPrint(
        'Cached progress for $audiobookId: ${(progressPercentage * 100).toStringAsFixed(1)}%',
      );
    } catch (e) {
      debugPrint("Error saving progress cache for $audiobookId: $e");
    }
  }

  /// Loads a cached progress percentage if available
  Future<double?> loadProgressCache(String audiobookId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_progressCachePrefix$audiobookId';
      if (prefs.containsKey(key)) {
        final progress = prefs.getDouble(key);
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
      final prefs = await SharedPreferences.getInstance();
      final key = '$_progressCachePrefix$audiobookId';
      await prefs.remove(key);
      debugPrint('Cleared cached progress for $audiobookId');
    } catch (e) {
      debugPrint("Error clearing progress cache for $audiobookId: $e");
    }
  }

  /// Resets all progress data for an audiobook (both position and progress cache)
  Future<void> resetAudiobookProgress(String audiobookId) async {
    try {
      await clearLastPosition(audiobookId);
      await _clearProgressCache(audiobookId);
      debugPrint('Reset all progress data for $audiobookId');
    } catch (e) {
      debugPrint("Error resetting progress for $audiobookId: $e");
    }
  }
}
