import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'; // For debugPrint

class StorageService {
  static const _foldersKey = 'audiobook_folders';
  static const _lastPositionPrefix = 'last_pos_';

  Future<void> saveAudiobookFolders(List<String> paths) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_foldersKey, paths);
      debugPrint("Saved audiobook folders: $paths");
    } catch (e) {
      debugPrint("Error saving audiobook folders: $e");
    }
  }

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
    // Input validation (optional but good practice)
    // assert(audiobookId.isNotEmpty, "audiobookId cannot be empty in saveLastPosition");
    // assert(chapterId.isNotEmpty, "chapterId cannot be empty in saveLastPosition");

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_lastPositionPrefix$audiobookId';
      // Store as "chapterId|milliseconds"
      final value = '$chapterId|${position.inMilliseconds}';
      await prefs.setString(key, value);
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
    // assert(audiobookId.isNotEmpty, "audiobookId cannot be empty in loadLastPosition");
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
            return {
              'chapterId': chapterId, // Non-nullable String
              'position': position, // Non-nullable Duration
            };
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
    // assert(audiobookId.isNotEmpty, "audiobookId cannot be empty in clearLastPosition");
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_lastPositionPrefix$audiobookId';
      await prefs.remove(key);
      debugPrint('Cleared position for $audiobookId');
    } catch (e) {
      debugPrint("Error clearing last position for $audiobookId: $e");
    }
  }
}
