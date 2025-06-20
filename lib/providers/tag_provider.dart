import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;

import '../models/tag.dart';

// Provider for the current tag sort option with persistence
final tagSortOptionProvider = StateNotifierProvider<TagSortOptionNotifier, TagSortOption>((ref) {
  return TagSortOptionNotifier();
});

// Provider for the current library sort option with persistence
final librarySortOptionProvider = StateNotifierProvider<LibrarySortOptionNotifier, LibrarySortOption>((ref) {
  return LibrarySortOptionNotifier();
});

// Provider for the current library mode (Library or Tags) with persistence
final libraryModeProvider = StateNotifierProvider<LibraryModeNotifier, LibraryMode>((ref) {
  return LibraryModeNotifier();
});

// Tag provider using StateNotifier
final tagProvider = StateNotifierProvider<TagNotifier, AsyncValue<List<Tag>>>((ref) {
  return TagNotifier(ref);
});

// Provider for audiobook tags mapping
final audiobookTagsProvider = StateNotifierProvider<AudiobookTagsNotifier, Map<String, Set<String>>>((ref) {
  return AudiobookTagsNotifier(ref);
});

// Combined provider that updates tag counts automatically
final syncedTagProvider = Provider<AsyncValue<List<Tag>>>((ref) {
  final tags = ref.watch(tagProvider);
  final audiobookTags = ref.watch(audiobookTagsProvider);
  
  return tags.when(
    data: (tagList) {
      // Calculate current tag counts
      final tagCounts = <String, int>{};
      for (final bookTags in audiobookTags.values) {
        for (final tagName in bookTags) {
          tagCounts[tagName] = (tagCounts[tagName] ?? 0) + 1;
        }
      }
      
      // Update tag counts and check if any have changed
      bool hasChanges = false;
      final updatedTags = tagList.map((tag) {
        final currentCount = tagCounts[tag.name] ?? 0;
        if (tag.bookCount != currentCount) {
          hasChanges = true;
          return tag.copyWith(bookCount: currentCount);
        }
        return tag;
      }).toList();
      
      // Only persist if there are significant changes (reduce persistence frequency)
      if (hasChanges) {
        // Schedule the persistence for next tick to avoid recursive provider updates
        Future.microtask(() async {
          try {
            final tagNotifier = ref.read(tagProvider.notifier);
            await tagNotifier.saveTags(updatedTags);
            if (kDebugMode) {
              debugPrint("Auto-synced tag counts: ${tagCounts.toString()}");
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint("Error auto-syncing tag counts: $e");
            }
          }
        });
      }
      
      return AsyncValue.data(updatedTags);
    },
    loading: () => const AsyncValue.loading(),
    error: (error, stackTrace) => AsyncValue.error(error, stackTrace),
  );
});

enum LibraryMode {
  library,
  tags,
}

extension LibraryModeExtension on LibraryMode {
  String get displayName {
    switch (this) {
      case LibraryMode.library:
        return 'Library';
      case LibraryMode.tags:
        return 'Tags';
    }
  }
}

class TagNotifier extends StateNotifier<AsyncValue<List<Tag>>> {
  TagNotifier(this.ref) : super(const AsyncValue.loading()) {
    loadTags();
  }

  final Ref ref;
  static const String _tagsKey = 'user_tags';

  /// Loads tags from storage
  Future<void> loadTags() async {
    try {
      state = const AsyncValue.loading();
      final prefs = await SharedPreferences.getInstance();
      final tagsJson = prefs.getString(_tagsKey);
      
      List<Tag> tags = [];
      
      if (tagsJson != null) {
        final List<dynamic> tagsList = json.decode(tagsJson);
        tags = tagsList.map((tagData) => Tag.fromJson(tagData)).toList();
      }

      // Always ensure Favorites tag exists and is first
      tags = await _ensureFavoritesTagExists(tags);

      state = AsyncValue.data(tags);
    } catch (error, stackTrace) {
      // Even on error, make sure we have at least the Favorites tag
      final favoritesTag = Tag(
        name: 'Favorites',
        createdAt: DateTime.now(),
        lastUsedAt: DateTime.now(),
        bookCount: 0,
        isFavorites: true,
      );
      state = AsyncValue.data([favoritesTag]);
      
      // Try to save the default state
      try {
        await _saveTags([favoritesTag]);
      } catch (saveError) {
        // If we can't save, at least we have the in-memory state
      }
    }
  }

  /// Ensures the Favorites tag always exists and is properly positioned
  Future<List<Tag>> _ensureFavoritesTagExists(List<Tag> tags) async {
    // Check if Favorites tag exists
    final favoritesIndex = tags.indexWhere((tag) => tag.isFavorites);
    
    if (favoritesIndex == -1) {
      // Create Favorites tag if it doesn't exist
      final favoritesTag = Tag(
        name: 'Favorites',
        createdAt: DateTime.now(),
        lastUsedAt: DateTime.now(),
        bookCount: 0,
        isFavorites: true,
      );
      tags.insert(0, favoritesTag); // Always insert at the beginning
      await _saveTags(tags);
    } else if (favoritesIndex != 0) {
      // Move Favorites to the beginning if it's not already there
      final favoritesTag = tags.removeAt(favoritesIndex);
      tags.insert(0, favoritesTag);
      await _saveTags(tags);
    }
    
    return tags;
  }

  /// Recalculates all tag counts based on current audiobook tags
  Future<void> recalculateTagCounts(Map<String, Set<String>> audiobookTags) async {
    final currentTags = await _ensureTagsLoaded();
    
    // Calculate new counts for each tag
    final tagCounts = <String, int>{};
    for (final bookTags in audiobookTags.values) {
      for (final tagName in bookTags) {
        tagCounts[tagName] = (tagCounts[tagName] ?? 0) + 1;
      }
    }

    // Update tags with new counts
    final updatedTags = currentTags.map((tag) {
      final newCount = tagCounts[tag.name] ?? 0;
      return tag.copyWith(bookCount: newCount);
    }).toList();

    await _saveTags(updatedTags);
    state = AsyncValue.data(updatedTags);
  }

  /// Cleans up orphaned tags (tags with 0 books) except Favorites
  Future<void> cleanupOrphanedTags() async {
    // DISABLED: User requested to keep orphaned tags
    if (kDebugMode) {
      debugPrint("Orphaned tag cleanup is disabled - keeping all tags even with 0 books");
    }
    return;
    
    /* Original code - now disabled:
    final currentTags = await _ensureTagsLoaded();
    
    // Remove tags with 0 book count, but preserve Favorites tag
    final cleanedTags = currentTags.where((tag) {
      return tag.isFavorites || tag.bookCount > 0;
    }).toList();
    
    if (cleanedTags.length != currentTags.length) {
      final removedCount = currentTags.length - cleanedTags.length;
      await saveTags(cleanedTags);
      state = AsyncValue.data(cleanedTags);
      debugPrint("Cleaned up $removedCount orphaned tags");
    }
    */
  }

  /// Recalculates tag counts and optionally cleans up orphaned tags
  Future<void> recalculateTagCountsWithCleanup(Map<String, Set<String>> audiobookTags, {bool cleanupOrphaned = false}) async {
    await recalculateTagCounts(audiobookTags);
    
    // Note: cleanupOrphaned is ignored because user requested to keep orphaned tags
    if (cleanupOrphaned && kDebugMode) {
      debugPrint("Orphaned tag cleanup was requested but is disabled per user preference");
    }
  }

  /// Creates a new tag with enhanced duplicate prevention
  Future<void> createTag(String name) async {
    if (name.trim().isEmpty) return;
    
    final currentTags = await _ensureTagsLoaded();
    final normalizedName = _normalizeTagName(name.trim());
    
    // Enhanced duplicate checking with similarity detection
    final existingTag = _findSimilarTag(currentTags, normalizedName);
    if (existingTag != null) {
      throw Exception('Tag with similar name "$existingTag" already exists');
    }

    final newTag = Tag(
      name: name.trim(),
      createdAt: DateTime.now(),
      lastUsedAt: DateTime.now(),
      bookCount: 0,
    );

    final updatedTags = [...currentTags, newTag];
    await _saveTags(updatedTags);
    state = AsyncValue.data(updatedTags);
  }

  /// Normalizes tag names for consistent comparison
  String _normalizeTagName(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '') // Remove special characters
        .replaceAll(RegExp(r'\s+'), ' ')    // Normalize whitespace
        .trim();
  }

  /// Finds similar existing tags to prevent near-duplicates
  String? _findSimilarTag(List<Tag> existingTags, String normalizedName) {
    for (final tag in existingTags) {
      final existingNormalized = _normalizeTagName(tag.name);
      
      // Exact match (case-insensitive, normalized)
      if (existingNormalized == normalizedName) {
        return tag.name;
      }
      
      // Series similarity detection
      if (_areSeriesSimilar(normalizedName, existingNormalized)) {
        return tag.name;
      }
    }
    return null;
  }

  /// Determines if two tag names represent the same series
  bool _areSeriesSimilar(String name1, String name2) {
    // Remove common series indicators and numbers
    final cleanName1 = _cleanSeriesName(name1);
    final cleanName2 = _cleanSeriesName(name2);
    
    // If the core series names are identical, consider them similar
    if (cleanName1 == cleanName2 && cleanName1.isNotEmpty) {
      return true;
    }
    
    // Check for very similar names (allowing for minor differences)
    if (cleanName1.length > 3 && cleanName2.length > 3) {
      final similarity = _calculateSimilarity(cleanName1, cleanName2);
      if (similarity > 0.85) { // 85% similarity threshold
        return true;
      }
    }
    
    return false;
  }

  /// Removes series indicators and numbers to get core series name
  String _cleanSeriesName(String name) {
    return name
        .replaceAll(RegExp(r'\b(?:series|book|vol|volume|part|chapter)\s*\d*\b'), '')
        .replaceAll(RegExp(r'\b\d+\b'), '') // Remove standalone numbers
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Calculates similarity between two strings using Levenshtein distance
  double _calculateSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;
    
    final distance = _levenshteinDistance(s1, s2);
    final maxLength = math.max(s1.length, s2.length);
    return 1.0 - (distance / maxLength);
  }

  /// Calculates Levenshtein distance between two strings
  int _levenshteinDistance(String s1, String s2) {
    final m = s1.length;
    final n = s2.length;
    
    if (m == 0) return n;
    if (n == 0) return m;
    
    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
    
    for (int i = 0; i <= m; i++) dp[i][0] = i;
    for (int j = 0; j <= n; j++) dp[0][j] = j;
    
    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        dp[i][j] = math.min(
          math.min(dp[i - 1][j] + 1, dp[i][j - 1] + 1),
          dp[i - 1][j - 1] + cost,
        );
      }
    }
    
    return dp[m][n];
  }

  /// Ensures tags are loaded and Favorites exists
  Future<List<Tag>> _ensureTagsLoaded() async {
    final currentState = state;
    if (currentState is AsyncData<List<Tag>>) {
      return currentState.value;
    } else {
      // If not loaded yet, load tags
      await loadTags();
      final newState = state;
      if (newState is AsyncData<List<Tag>>) {
        return newState.value;
      } else {
        // Fallback: return at least Favorites
        return [
          Tag(
            name: 'Favorites',
            createdAt: DateTime.now(),
            lastUsedAt: DateTime.now(),
            bookCount: 0,
            isFavorites: true,
          )
        ];
      }
    }
  }

  /// Deletes a tag (except Favorites)
  Future<void> deleteTag(String name) async {
    final currentTags = await _ensureTagsLoaded();
    final tag = currentTags.firstWhere((t) => t.name == name, orElse: () => throw Exception('Tag not found'));
    
    if (tag.isFavorites) {
      throw Exception('Cannot delete the Favorites tag');
    }

    final updatedTags = currentTags.where((tag) => tag.name != name).toList();
    await _saveTags(updatedTags);
    state = AsyncValue.data(updatedTags);
  }

  /// Renames a tag (except Favorites)
  Future<void> renameTag(String oldName, String newName) async {
    final currentTags = await _ensureTagsLoaded();
    final tag = currentTags.firstWhere((t) => t.name == oldName, orElse: () => throw Exception('Tag not found'));
    
    if (tag.isFavorites) {
      throw Exception('Cannot rename the Favorites tag');
    }

    // Check if new name already exists
    if (currentTags.any((t) => t.name == newName)) {
      throw Exception('A tag with this name already exists');
    }

    // Update the tag name while preserving other properties
    final updatedTags = currentTags.map((t) {
      if (t.name == oldName) {
        return t.copyWith(name: newName);
      }
      return t;
    }).toList();

    await _saveTags(updatedTags);
    state = AsyncValue.data(updatedTags);

    // Also need to update audiobook tags mapping
    final audiobookTagsNotifier = ref.read(audiobookTagsProvider.notifier);
    await audiobookTagsNotifier.renameTagInAllAudiobooks(oldName, newName);
  }

  /// Updates tag usage timestamp
  Future<void> updateTagUsage(String name) async {
    final currentTags = await _ensureTagsLoaded();
    final updatedTags = currentTags.map((tag) {
      if (tag.name == name) {
        return tag.copyWith(lastUsedAt: DateTime.now());
      }
      return tag;
    }).toList();

    await _saveTags(updatedTags);
    state = AsyncValue.data(updatedTags);
  }

  /// Updates book count for a tag
  Future<void> updateTagBookCount(String tagName, int newCount) async {
    final currentTags = await _ensureTagsLoaded();
    final updatedTags = currentTags.map((tag) {
      if (tag.name == tagName) {
        return tag.copyWith(bookCount: newCount);
      }
      return tag;
    }).toList();

    await _saveTags(updatedTags);
    state = AsyncValue.data(updatedTags);
  }

  /// Gets sorted tags based on the current sort option
  List<Tag> getSortedTags(TagSortOption sortOption) {
    final tags = state.asData?.value ?? [];
    final List<Tag> sortedTags = List.from(tags);

    // Always keep Favorites first
    final favorites = sortedTags.where((tag) => tag.isFavorites).toList();
    final others = sortedTags.where((tag) => !tag.isFavorites).toList();

    switch (sortOption) {
      case TagSortOption.alphabeticalAZ:
        others.sort((a, b) => a.name.compareTo(b.name));
        break;
      case TagSortOption.alphabeticalZA:
        others.sort((a, b) => b.name.compareTo(a.name));
        break;
      case TagSortOption.recentlyUsed:
        others.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
        break;
      case TagSortOption.recentlyCreated:
        others.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }

    return [...favorites, ...others];
  }

  /// Saves tags to storage (made public for syncedTagProvider)
  Future<void> saveTags(List<Tag> tags) async {
    await _saveTags(tags);
  }

  /// Private method to save tags to SharedPreferences
  Future<void> _saveTags(List<Tag> tags) async {
    try {
    final prefs = await SharedPreferences.getInstance();
    final tagsJson = json.encode(tags.map((tag) => tag.toJson()).toList());
    await prefs.setString(_tagsKey, tagsJson);
      debugPrint("Saved ${tags.length} tags to storage");
    } catch (error) {
      debugPrint("Error saving tags: $error");
      rethrow;
    }
  }

  /// Finds the most similar existing tag for a given name
  String? findMostSimilarTag(String name) {
    final currentState = state;
    if (currentState is! AsyncData<List<Tag>>) return null;
    
    final currentTags = currentState.value;
    final normalizedName = _normalizeTagName(name.trim());
    
    return _findSimilarTag(currentTags, normalizedName);
  }

  /// Suggests an available tag name based on the given name
  String suggestAvailableTagName(String baseName) {
    final currentState = state;
    if (currentState is! AsyncData<List<Tag>>) return baseName;
    
    final currentTags = currentState.value;
    final normalizedBase = _normalizeTagName(baseName.trim());
    
    // If no similar tag exists, return the original name
    if (_findSimilarTag(currentTags, normalizedBase) == null) {
      return baseName.trim();
    }
    
    // Try variations with numbers
    for (int i = 2; i <= 10; i++) {
      final candidate = "${baseName.trim()} $i";
      final normalizedCandidate = _normalizeTagName(candidate);
      
      if (_findSimilarTag(currentTags, normalizedCandidate) == null) {
        return candidate;
      }
    }
    
    // Fallback: add timestamp
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString().substring(8);
    return "${baseName.trim()} $timestamp";
  }
}

class AudiobookTagsNotifier extends StateNotifier<Map<String, Set<String>>> {
  AudiobookTagsNotifier(this.ref) : super({}) {
    loadAudiobookTags();
  }

  final Ref ref;
  static const String _audiobookTagsKey = 'audiobook_tags';

  /// Loads audiobook tags mapping from storage
  Future<void> loadAudiobookTags() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tagsJson = prefs.getString(_audiobookTagsKey);
      
      if (tagsJson != null) {
        final Map<String, dynamic> tagsData = json.decode(tagsJson);
        final Map<String, Set<String>> audiobookTags = {};
        
        for (final entry in tagsData.entries) {
          audiobookTags[entry.key] = Set<String>.from(entry.value as List);
        }
        
        state = audiobookTags;
      }
    } catch (error) {
      // Handle error silently, start with empty state
      state = {};
    }
  }

  /// Adds a tag to an audiobook
  Future<void> addTagToAudiobook(String audiobookId, String tagName) async {
    final currentTags = Map<String, Set<String>>.from(state);
    final bookTags = currentTags[audiobookId] ?? <String>{};
    bookTags.add(tagName);
    currentTags[audiobookId] = bookTags;
    
    state = currentTags;
    await _saveAudiobookTags();
  }

  /// Removes a tag from an audiobook
  Future<void> removeTagFromAudiobook(String audiobookId, String tagName) async {
    final currentTags = Map<String, Set<String>>.from(state);
    final bookTags = currentTags[audiobookId];
    if (bookTags != null) {
      bookTags.remove(tagName);
      if (bookTags.isEmpty) {
        currentTags.remove(audiobookId);
      } else {
        currentTags[audiobookId] = bookTags;
      }
    }
    
    state = currentTags;
    await _saveAudiobookTags();
  }

  /// Toggles favorite status for an audiobook
  Future<void> toggleFavorite(String audiobookId) async {
    final currentTags = Map<String, Set<String>>.from(state);
    final bookTags = currentTags[audiobookId] ?? <String>{};
    
    if (bookTags.contains('Favorites')) {
      bookTags.remove('Favorites');
    } else {
      bookTags.add('Favorites');
    }
    
    if (bookTags.isEmpty) {
      currentTags.remove(audiobookId);
    } else {
      currentTags[audiobookId] = bookTags;
    }
    
    state = currentTags;
    await _saveAudiobookTags();
  }

  /// Gets all audiobooks with a specific tag
  List<String> getAudiobooksByTag(String tagName) {
    return state.entries
        .where((entry) => entry.value.contains(tagName))
        .map((entry) => entry.key)
        .toList();
  }

  /// Gets all tags for an audiobook
  Set<String> getTagsForAudiobook(String audiobookId) {
    return state[audiobookId] ?? <String>{};
  }

  /// Gets all unique tags
  Set<String> getAllTags() {
    final allTags = <String>{};
    for (final tags in state.values) {
      allTags.addAll(tags);
    }
    return allTags;
  }

  /// Renames a tag in all audiobook mappings
  Future<void> renameTagInAllAudiobooks(String oldName, String newName) async {
    final currentTags = Map<String, Set<String>>.from(state);
    bool hasChanges = false;
    
    for (final entry in currentTags.entries) {
      if (entry.value.contains(oldName)) {
        entry.value.remove(oldName);
        entry.value.add(newName);
        hasChanges = true;
      }
    }
    
    if (hasChanges) {
      state = currentTags;
      await _saveAudiobookTags();
    }
  }

  /// Saves audiobook tags to storage
  Future<void> _saveAudiobookTags() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, List<String>> serializableData = {};
    
    for (final entry in state.entries) {
      serializableData[entry.key] = entry.value.toList();
    }
    
    final tagsJson = json.encode(serializableData);
    await prefs.setString(_audiobookTagsKey, tagsJson);
  }

  /// Removes all tags from an audiobook (used when book is deleted)
  Future<void> removeAllTagsFromAudiobook(String audiobookId) async {
    final currentTags = Map<String, Set<String>>.from(state);
    if (currentTags.containsKey(audiobookId)) {
      currentTags.remove(audiobookId);
      state = currentTags;
      await _saveAudiobookTags();
    }
  }

  /// Updates an audiobook's ID when its path changes (renames/moves)
  Future<void> updateAudiobookId(String oldId, String newId) async {
    final currentTags = Map<String, Set<String>>.from(state);
    if (currentTags.containsKey(oldId)) {
      // Move tags from old ID to new ID
      currentTags[newId] = currentTags[oldId]!;
      currentTags.remove(oldId);
      state = currentTags;
      await _saveAudiobookTags();
    }
  }
}

/// StateNotifier for persistent tag sort option
class TagSortOptionNotifier extends StateNotifier<TagSortOption> {
  static const String _tagSortKey = 'tag_sort_option';
  
  TagSortOptionNotifier() : super(TagSortOption.alphabeticalAZ) {
    _loadSortOption();
  }

  Future<void> _loadSortOption() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedOption = prefs.getString(_tagSortKey);
      if (savedOption != null) {
        // Find the matching enum value
        for (final option in TagSortOption.values) {
          if (option.toString() == savedOption) {
            state = option;
            break;
          }
        }
      }
    } catch (e) {
      debugPrint("Error loading tag sort option: $e");
    }
  }

  Future<void> updateSortOption(TagSortOption newOption) async {
    state = newOption;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tagSortKey, newOption.toString());
      debugPrint("Saved tag sort option: ${newOption.displayName}");
    } catch (e) {
      debugPrint("Error saving tag sort option: $e");
    }
  }
}

/// StateNotifier for persistent library sort option
class LibrarySortOptionNotifier extends StateNotifier<LibrarySortOption> {
  static const String _librarySortKey = 'library_sort_option';
  
  LibrarySortOptionNotifier() : super(LibrarySortOption.lastPlayedRecent) {
    _loadSortOption();
  }

  Future<void> _loadSortOption() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedOption = prefs.getString(_librarySortKey);
      if (savedOption != null) {
        // Find the matching enum value
        for (final option in LibrarySortOption.values) {
          if (option.toString() == savedOption) {
            state = option;
            break;
          }
        }
      }
    } catch (e) {
      debugPrint("Error loading library sort option: $e");
    }
  }

  Future<void> updateSortOption(LibrarySortOption newOption) async {
    state = newOption;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_librarySortKey, newOption.toString());
      debugPrint("Saved library sort option: ${newOption.displayName}");
    } catch (e) {
      debugPrint("Error saving library sort option: $e");
    }
  }
}

/// StateNotifier for persistent library mode
class LibraryModeNotifier extends StateNotifier<LibraryMode> {
  static const String _libraryModeKey = 'library_mode';
  
  LibraryModeNotifier() : super(LibraryMode.library) {
    _loadLibraryMode();
  }

  Future<void> _loadLibraryMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getString(_libraryModeKey);
      if (savedMode != null) {
        // Find the matching enum value
        for (final mode in LibraryMode.values) {
          if (mode.toString() == savedMode) {
            state = mode;
            break;
          }
        }
      }
    } catch (e) {
      debugPrint("Error loading library mode: $e");
    }
  }

  Future<void> updateLibraryMode(LibraryMode newMode) async {
    state = newMode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_libraryModeKey, newMode.toString());
      debugPrint("Saved library mode: ${newMode.displayName}");
    } catch (e) {
      debugPrint("Error saving library mode: $e");
    }
  }
} 