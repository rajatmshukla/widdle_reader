import 'dart:io'; // For Platform and Directory
import 'dart:async'; // For unawaited, Timer
import 'dart:typed_data'; // For Uint8List
import 'package:flutter/foundation.dart'; // For debugPrint and ChangeNotifier
import 'package:flutter/widgets.dart'; // For WidgetsBinding
import 'package:permission_handler/permission_handler.dart'; // For permissions
import 'package:file_picker/file_picker.dart'; // For picking folders
import 'package:device_info_plus/device_info_plus.dart'; // For Android version check
import 'package:flutter_riverpod/flutter_riverpod.dart'; // For WidgetRef
import 'package:path/path.dart' as p; // For path operations
// import 'package:shared_preferences/shared_preferences.dart'; // For SharedPreferences - not needed directly

// Import local models and services
import '../models/audiobook.dart';

import '../models/chapter.dart';
import '../models/tag.dart'; // Contains LibrarySortOption
import '../services/metadata_service.dart';
import '../services/storage_service.dart';
import '../services/auto_tag_service.dart';
import '../services/cover_art_service.dart';
import '../providers/tag_provider.dart';

// CRITICAL FIX: Add release-safe logging
void _logDebug(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
  // Removed release mode logging to improve performance
}

void _logCritical(String message) {
  // Only log critical messages in debug mode to avoid performance issues
  if (kDebugMode) {
    print("[CRITICAL] $message");
  }
}

// LibrarySortOption moved to models/tag.dart to avoid duplication

class AudiobookProvider extends ChangeNotifier with WidgetsBindingObserver {
  final MetadataService _metadataService = MetadataService();
  final StorageService _storageService = StorageService();
  
  // Store the root path for auto-tag creation
  String? _lastScannedRootPath;
  List<String>? _lastAddedPaths;

  List<Audiobook> _audiobooks = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _permissionPermanentlyDenied = false;

  // Map to store the last played timestamps for each audiobook
  final Map<String, int> _lastPlayedTimestamps = {};

  // Map to store which books are completed
  final Map<String, bool> _completedBooks = {};

  // Map to store which books are new (never played)
  final Map<String, bool> _newBooks = {};

  // New property for custom titles
  final Map<String, String> _customTitles = {};

  // Current sort option to prevent unnecessary re-sorting
  LibrarySortOption? _currentSortOption;

  // Getters for state
  List<Audiobook> get audiobooks => _audiobooks;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get permissionPermanentlyDenied => _permissionPermanentlyDenied;

  // Getters for filtered book lists
  // Getters for filtered book lists
  List<Audiobook> get ongoingBooks => _audiobooks.where((book) => !(_completedBooks[book.id] ?? false)).toList();
  List<Audiobook> get completedBooksOnly => _audiobooks.where((book) => _completedBooks[book.id] ?? false).toList();
  List<Audiobook> get reviewedBooks => _audiobooks.where((book) => book.rating != null || (book.review != null && book.review!.isNotEmpty)).toList();
  
  // Keep detailed loading getters for compatibility but they now just return default values
  bool get isDetailedLoading => _isLoading;
  String get currentLoadingStep => '';
  String get currentLoadingFile => '';
  int get totalFilesToProcess => 0;
  int get filesProcessed => 0;
  double get loadingProgress => 0.0;
  List<String> get activityLog => [];
  List<String> get detailedStats => [];

  // New getters for book state
  bool isNewBook(String audiobookId) => _newBooks[audiobookId] ?? false;
  bool isCompletedBook(String audiobookId) =>
      _completedBooks[audiobookId] ?? false;
  
  // Getter for custom titles
  Map<String, String> get customTitles => Map.from(_customTitles);
  
  // Getters for auto-tag information
  String? get lastScannedRootPath => _lastScannedRootPath;
  List<String>? get lastAddedPaths => _lastAddedPaths?.toList();

  // Constructor: Load audiobooks when the provider is created
  AudiobookProvider() {
    // Register lifecycle observer
    WidgetsBinding.instance.addObserver(this);
    
    // Listen for data restore events to prevent stale state
    _storageService.addRestoreListener(_onDataRestored);
    
    _loadCustomTitles().then((_) => loadAudiobooks());
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _logDebug("App resumed. Syncing library to remove deleted books...");
      syncDeletedBooksOnly();
    }
  }
  
  void _onDataRestored() {
    _logDebug("Restore detected, reloading audiobooks...");
    loadAudiobooks();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _storageService.removeRestoreListener(_onDataRestored);
    super.dispose();
  }
  
  // Guard to prevent concurrent sync operations
  bool _isSyncing = false;
  
  /// Syncs library to remove deleted books without full reload
  Future<void> syncDeletedBooksOnly() async {
    // Prevent concurrent sync runs
    if (_isSyncing) {
      _logDebug("Sync already in progress, skipping...");
      return;
    }
    _isSyncing = true;
    
    try {
      final List<String> folderPaths = await _storageService.loadAudiobookFolders();
      final List<String> validPaths = [];
      final List<String> deletedPaths = [];
      
      for (final path in folderPaths) {
        try {
          if (await Directory(path).exists()) {
            validPaths.add(path);
          } else {
            deletedPaths.add(path);
          }
        } catch (e) {
          // If we can't check the path (permission issue?), assume it's valid to be safe
          _logDebug("Error checking path existence: $path - $e");
          validPaths.add(path);
        }
      }
      
      if (deletedPaths.isNotEmpty) {
        _logDebug("Sync found ${deletedPaths.length} deleted audiobooks. Removing...");
        
        for (final path in deletedPaths) {
          // Clean up storage service data
          await _storageService.removeAudiobookData(path);
          
          // Clean up in-memory maps
          _customTitles.remove(path);
          _completedBooks.remove(path);
          _newBooks.remove(path);
          _lastPlayedTimestamps.remove(path);
        }
        
        // Persist custom titles after removal
        await _saveCustomTitles();
        
        // Update storage
        await _storageService.saveAudiobookFolders(validPaths);
        
        // Update in-memory list
        _audiobooks.removeWhere((book) => deletedPaths.contains(book.id));
        
        notifyListeners();
        _logDebug("Successfully removed ${deletedPaths.length} deleted audiobooks.");
      }
    } catch (e) {
      _logDebug("Error syncing deleted books: $e");
    } finally {
      _isSyncing = false;
    }
  }

  /// Loads saved custom titles from preferences
  Future<void> _loadCustomTitles() async {
    try {
      final savedTitles = await _storageService.loadCustomTitles();
      _customTitles.clear();
      _customTitles.addAll(savedTitles);
      _logDebug("Loaded ${_customTitles.length} custom titles");
    } catch (e) {
      _logDebug("Error loading custom titles: $e");
    }
  }

  /// Saves custom titles to preferences
  Future<void> _saveCustomTitles() async {
    try {
      await _storageService.saveCustomTitles(_customTitles);
      _logDebug("Saved ${_customTitles.length} custom titles");
    } catch (e) {
      _logDebug("Error saving custom titles: $e");
    }
  }

  /// Gets the title for an audiobook, using custom title if available
  String getTitleForAudiobook(Audiobook book) {
    return _customTitles[book.id] ?? book.title;
  }

  /// Sets a custom title for an audiobook
  Future<void> setCustomTitle(String audiobookId, String newTitle) async {
    if (newTitle.trim().isEmpty) {
      // If empty, remove the custom title
      _customTitles.remove(audiobookId);
    } else {
      // Otherwise save the new title
      _customTitles[audiobookId] = newTitle.trim();
    }

    await _saveCustomTitles();

    // Update the display
    notifyListeners();
  }

  /// Updates the cover art for an audiobook
  Future<void> updateAudiobookCover(String audiobookId, Uint8List coverData) async {
    final index = _audiobooks.indexWhere((b) => b.id == audiobookId);
    if (index != -1) {
      // Update in-memory model
      _audiobooks[index] = _audiobooks[index].copyWith(coverArt: coverData);
      
      // Update cache
      await _storageService.saveCachedCoverArt(audiobookId, coverData);
      
      notifyListeners();
    }
  }

  // Method to refresh UI without reloading audiobooks
  void refreshUI() {
    notifyListeners();
  }

  /// Clears any error messages
  void clearErrorMessage() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Start loading
  void _startLoading() {
    _isLoading = true;
    notifyListeners();
  }

  /// Stop loading with guaranteed state clearing
  void _stopLoading() {
    _logDebug("CRITICAL: _stopLoading() called - forcing loading to stop");
    
    // Force loading state to false with multiple safety checks
    _isLoading = false;
    
    // Ensure UI update happens immediately on main thread
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isLoading) {
        _logCritical("CRITICAL BUG: Loading state still true after _stopLoading!");
        _isLoading = false;
        notifyListeners();
      }
    });
    
    // Primary notification
    notifyListeners();
    
    _logDebug("CRITICAL: _stopLoading() completed - isLoading should be false: $_isLoading");
  }

  /// Force stop loading with maximum safety measures for release builds
  void _forceStopLoading() {
    _logDebug("FORCE STOP: Multiple safety mechanisms to ensure loading stops");
    
    // 1. Set loading to false immediately
    _isLoading = false;
    
    // 2. Schedule immediate UI update
    notifyListeners();
    
    // 3. Double-check with delayed callback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isLoading) {
        _logCritical("EMERGENCY: Loading state persisted, forcing clear!");
        _isLoading = false;
        notifyListeners();
      }
    });
    
    // 4. Add a backup timer for extreme cases (release build protection)
    Timer(const Duration(milliseconds: 100), () {
      if (_isLoading) {
        _logCritical("BACKUP TIMER: Loading state still persisted, emergency clear!");
        _isLoading = false;
        if (mounted) notifyListeners();
      }
    });
    
    _logDebug("FORCE STOP: All safety mechanisms activated");
  }

  /// Check if the provider is still mounted (for safety)
  bool get mounted => true; // ChangeNotifier is always considered mounted

  /// Loads the last played timestamps for all audiobooks
  Future<void> _loadLastPlayedTimestamps() async {
    _lastPlayedTimestamps.clear();
    _completedBooks.clear();
    _newBooks.clear();

    for (final book in _audiobooks) {
      // Get last played timestamp
      final timestamp = await _storageService.getLastPlayedTimestamp(book.id);
      _lastPlayedTimestamps[book.id] = timestamp;

      // Check if book is completed
      final isCompleted = await _storageService.isCompleted(book.id);
      _completedBooks[book.id] = isCompleted;

      // Calculate progress percentage to confirm completion status
      final progress = await _storageService.loadProgressCache(book.id) ?? 0.0;
      if (progress >= 0.99) {
        _completedBooks[book.id] = true;
        await _storageService.markAsCompleted(book.id);
      }

      // If timestamp is 0, the book has never been played (it's new)
      _newBooks[book.id] = timestamp == 0;
    }

    // Sort audiobooks based on completion status and last played time
    _sortAudiobooksByStatus();
  }

  /// Sorts audiobooks based on the provided sort option
  void sortAudiobooks(LibrarySortOption sortOption) {
    // Update the current sort option regardless of whether we skip sorting
    _currentSortOption = sortOption;
    
    // Skip sorting if the option hasn't changed and we have books
    if (_audiobooks.isEmpty) {
      return; // No books to sort
    }
    
    switch (sortOption) {
      case LibrarySortOption.alphabeticalAZ:
        _audiobooks.sort((a, b) {
          final titleA = getTitleForAudiobook(a).toLowerCase();
          final titleB = getTitleForAudiobook(b).toLowerCase();
          return titleA.compareTo(titleB);
        });
        break;
        
      case LibrarySortOption.alphabeticalZA:
        _audiobooks.sort((a, b) {
          final titleA = getTitleForAudiobook(a).toLowerCase();
          final titleB = getTitleForAudiobook(b).toLowerCase();
          return titleB.compareTo(titleA);
        });
        break;
        
      case LibrarySortOption.authorAZ:
        _audiobooks.sort((a, b) {
          final authorA = (a.author ?? 'Unknown').toLowerCase();
          final authorB = (b.author ?? 'Unknown').toLowerCase();
          return authorA.compareTo(authorB);
        });
        break;
        
      case LibrarySortOption.authorZA:
        _audiobooks.sort((a, b) {
          final authorA = (a.author ?? 'Unknown').toLowerCase();
          final authorB = (b.author ?? 'Unknown').toLowerCase();
          return authorB.compareTo(authorA);
        });
        break;
        
      case LibrarySortOption.dateAddedNewest:
        // Sort by file creation time (newest first)
        _audiobooks.sort((a, b) {
          try {
            final dirA = Directory(a.id);
            final dirB = Directory(b.id);
            final statA = dirA.statSync();
            final statB = dirB.statSync();
            return statB.modified.compareTo(statA.modified);
          } catch (e) {
            return 0; // If stat fails, maintain current order
          }
        });
        break;
        
      case LibrarySortOption.dateAddedOldest:
        // Sort by file creation time (oldest first)
        _audiobooks.sort((a, b) {
          try {
            final dirA = Directory(a.id);
            final dirB = Directory(b.id);
            final statA = dirA.statSync();
            final statB = dirB.statSync();
            return statA.modified.compareTo(statB.modified);
          } catch (e) {
            return 0; // If stat fails, maintain current order
          }
        });
        break;
        
      case LibrarySortOption.lastPlayedRecent:
        // Sort by last played (most recent first)
        _audiobooks.sort((a, b) {
          final aTimestamp = _lastPlayedTimestamps[a.id] ?? 0;
          final bTimestamp = _lastPlayedTimestamps[b.id] ?? 0;
          return bTimestamp.compareTo(aTimestamp);
        });
        break;
        
      case LibrarySortOption.lastPlayedOldest:
        // Sort by last played (oldest first)
        _audiobooks.sort((a, b) {
          final aTimestamp = _lastPlayedTimestamps[a.id] ?? 0;
          final bTimestamp = _lastPlayedTimestamps[b.id] ?? 0;
          return aTimestamp.compareTo(bTimestamp);
        });
        break;
        
      case LibrarySortOption.series:
        // Sort by series (group books that look like they're in a series)
        _audiobooks.sort((a, b) {
          final titleA = getTitleForAudiobook(a).toLowerCase();
          final titleB = getTitleForAudiobook(b).toLowerCase();
          
          // Extract potential series name and number
          final seriesA = _extractSeriesInfo(titleA);
          final seriesB = _extractSeriesInfo(titleB);
          
          // First sort by series name
          final seriesCompare = seriesA['name'].compareTo(seriesB['name']);
          if (seriesCompare != 0) return seriesCompare;
          
          // Then by book number within series
          return seriesA['number'].compareTo(seriesB['number']);
        });
        break;
        
      case LibrarySortOption.completionStatus:
        // Sort by completion status (incomplete first, then completed, within each group by recency)
    _audiobooks.sort((a, b) {
      final aCompleted = _completedBooks[a.id] ?? false;
      final bCompleted = _completedBooks[b.id] ?? false;

      // If one book is completed and the other isn't, the completed one goes to the bottom
      if (aCompleted && !bCompleted) {
        return 1; // a (completed) goes after b
      } else if (!aCompleted && bCompleted) {
        return -1; // a (not completed) goes before b
      }

      // If both are completed or both are not completed, sort by recency
      final aTimestamp = _lastPlayedTimestamps[a.id] ?? 0;
      final bTimestamp = _lastPlayedTimestamps[b.id] ?? 0;
      return bTimestamp.compareTo(aTimestamp);
    });
        break;
    }
    
    // Save the sorted order to storage
    _saveSortedOrder();
    
    // Notify listeners to update the UI
    notifyListeners();
  }

  /// Saves the current sorted order of audiobooks to storage
  Future<void> _saveSortedOrder() async {
    try {
      final sortedPaths = _audiobooks.map((book) => book.id).toList();
      await _storageService.saveAudiobookFolders(sortedPaths);
      _logDebug("Saved sorted audiobook order: ${sortedPaths.length} books");
    } catch (e) {
      _logDebug("Error saving sorted order: $e");
    }
  }

  /// Extract series information from a book title
  Map<String, dynamic> _extractSeriesInfo(String title) {
    // Look for patterns like "Series Name 1", "Series Name - Book 1", "Series Name: Part 1", etc.
    final patterns = [
      RegExp(r'^(.+?)\s+(\d+)$'), // "Series Name 1"
      RegExp(r'^(.+?)\s*-\s*(?:book|vol|volume|part)\s*(\d+)', caseSensitive: false), // "Series - Book 1"
      RegExp(r'^(.+?)\s*:\s*(?:book|vol|volume|part)\s*(\d+)', caseSensitive: false), // "Series: Book 1"
      RegExp(r'^(.+?)\s*\((?:book|vol|volume|part)\s*(\d+)\)', caseSensitive: false), // "Series (Book 1)"
    ];
    
    for (final pattern in patterns) {
      final match = pattern.firstMatch(title);
      if (match != null) {
        return {
          'name': match.group(1)?.trim() ?? title,
          'number': int.tryParse(match.group(2) ?? '0') ?? 0,
        };
      }
    }
    
    // If no pattern matches, use the full title as series name with number 0
    return {
      'name': title,
      'number': 0,
    };
  }

  /// Saves a review for an audiobook
  Future<void> saveReview(String audiobookId, double rating, String? reviewContent) async {
    try {
      final now = DateTime.now();
      // Save to storage with explicit timestamp to ensure consistency
      await _storageService.saveAudiobookReview(audiobookId, rating, reviewContent, timestamp: now);
      
      // Update local state
      final index = _audiobooks.indexWhere((b) => b.id == audiobookId);
      if (index != -1) {
        _audiobooks[index] = _audiobooks[index].copyWith(
          rating: rating,
          review: reviewContent,
          reviewTimestamp: now,
        );
        notifyListeners();
      }
    } catch (e) {
      _logDebug("Error saving review for $audiobookId: $e");
      rethrow;
    }
  }

  /// Sorts audiobooks with completed books at the bottom and others by recently played (legacy method, now replaced by sortAudiobooks)
  void _sortAudiobooksByStatus() {
    // Use the current sort option if available, otherwise default to completion status
    final sortOption = _currentSortOption ?? LibrarySortOption.lastPlayedRecent;
    sortAudiobooks(sortOption);
  }

  /// Sets the current sort option (called from UI when sort preference is loaded/changed)
  void setCurrentSortOption(LibrarySortOption sortOption) {
    _currentSortOption = sortOption;
  }

  /// Records when a book is played, updates its timestamp and moves it accordingly in the list
  Future<void> recordBookPlayed(String audiobookId) async {
    // Update timestamp in storage
    await _storageService.updateLastPlayedTimestamp(audiobookId);

    // Update in-memory timestamp
    _lastPlayedTimestamps[audiobookId] = DateTime.now().millisecondsSinceEpoch;

    // Mark as not new anymore
    _newBooks[audiobookId] = false;

    // Check if the book is completed (>99% progress)
    final progress =
        await _storageService.loadProgressCache(audiobookId) ?? 0.0;
    if (progress >= 0.99) {
      _completedBooks[audiobookId] = true;
      await _storageService.markAsCompleted(audiobookId);
    } else {
      _completedBooks[audiobookId] = false;
      await _storageService.unmarkAsCompleted(audiobookId);
    }

    // Re-sort to ensure proper positioning
    _sortAudiobooksByStatus();

    // Notify listeners to refresh UI
    notifyListeners();
  }

  /// Marks a book as completed without playing it (for testing or manual completion)
  Future<void> markBookAsCompleted(String audiobookId) async {
    _completedBooks[audiobookId] = true;
    await _storageService.markAsCompleted(audiobookId);
    await _storageService.saveProgressCache(audiobookId, 1.0); // 100% progress

    // Re-sort to move the book to the bottom
    _sortAudiobooksByStatus();

    // Notify listeners to refresh UI
    notifyListeners();
  }

  /// Toggles the completion status of a book manually
  Future<void> toggleCompletionStatus(String audiobookId) async {
    final isCompleted = _completedBooks[audiobookId] ?? false;
    
    if (isCompleted) {
      // Mark as unfinished
      _completedBooks[audiobookId] = false;
      await _storageService.unmarkAsCompleted(audiobookId);
      // We don't reset progress to 0 here, assuming user wants to keep progress but mark as "reading"
    } else {
      // Mark as finished
      _completedBooks[audiobookId] = true;
      await _storageService.markAsCompleted(audiobookId);
      await _storageService.saveProgressCache(audiobookId, 1.0); // 100% progress
    }
    
    // Re-sort to move the book accordingly
    _sortAudiobooksByStatus();
    
    // Notify listeners to refresh UI
    notifyListeners();
  }

  /// Updates completion status based on progress and reorder books accordingly
  Future<void> updateCompletionStatus(String audiobookId) async {
    // Get current progress percentage
    final progress =
        await _storageService.loadProgressCache(audiobookId) ?? 0.0;

    // Consider book completed if progress is ≥99%
    if (progress >= 0.99) {
      if (!(_completedBooks[audiobookId] ?? false)) {
        _completedBooks[audiobookId] = true;
        await _storageService.markAsCompleted(audiobookId);

        // Re-sort books to move this one to the bottom
        _sortAudiobooksByStatus();
        notifyListeners();
      }
    } else {
      // If progress is <99% but book was marked as completed before, unmark it
      if (_completedBooks[audiobookId] ?? false) {
        _completedBooks[audiobookId] = false;
        await _storageService.unmarkAsCompleted(audiobookId);

        // Re-sort books
        _sortAudiobooksByStatus();
        notifyListeners();
      }
    }
  }

  /// Creates and assigns auto-tags for multiple audiobooks using AutoTagService
  Future<void> createAutoTagsForMultipleBooks(
    List<String> audiobookPaths, 
    String rootPath,
    WidgetRef ref
  ) async {
    try {
      _logDebug("Starting auto-tag creation for ${audiobookPaths.length} audiobooks");
      
      final autoTagService = AutoTagService(ref);
      final result = await autoTagService.createAutoTagsForAudiobooks(
        audiobookPaths: audiobookPaths,
        rootPath: rootPath,
        createTags: true,
        assignTags: true,
      );
      
      if (result.hasSuccess) {
        _logDebug("Auto-tag creation successful: ${result.summary}");
        
        // Update error message to show success
        _errorMessage = null;
        
        // Show success message in debug log
        if (result.createdTags.isNotEmpty) {
          _logDebug("Created tags: ${result.createdTags.join(', ')}");
        }
        if (result.totalAssignments > 0) {
          _logDebug("Made ${result.totalAssignments} tag assignments");
        }
        
      } else if (result.hasError) {
        _logDebug("Auto-tag creation failed: ${result.error}");
      } else {
        _logDebug("No auto-tags created (no suitable folder structure found)");
      }
      
    } catch (e) {
      _logDebug("Error in auto-tag creation: $e");
    }
  }

  /// Creates and assigns auto-tags for a single audiobook
  Future<void> createAutoTagsForSingleBook(
    String audiobookPath, 
    String rootPath,
    WidgetRef ref
  ) async {
    try {
      _logDebug("Starting auto-tag creation for single audiobook: ${audiobookPath.split('/').last}");
      
      final autoTagService = AutoTagService(ref);
      final result = await autoTagService.createAutoTagsForAudiobooks(
        audiobookPaths: [audiobookPath],
        rootPath: rootPath,
        createTags: true,
        assignTags: true,
      );
      
      if (result.hasSuccess) {
        _logDebug("Auto-tag creation successful for single book: ${result.summary}");
        
        // Update error message to show success
        _errorMessage = null;
        
      } else if (result.hasError) {
        _logDebug("Auto-tag creation failed for single book: ${result.error}");
      } else {
        _logDebug("No auto-tags created for single book (no suitable folder structure found)");
      }
      
    } catch (e) {
      _logDebug("Error in single book auto-tag creation: $e");
    }
  }

  /// OPTIMIZED APPROACH: Fast startup with immediate UI display
  Future<void> loadAudiobooks() async {
    _logDebug("=== FAST STARTUP: loadAudiobooks started ===");
    
    // CRITICAL FIX: Never show loading state on startup - show UI immediately
    _isLoading = false;
    _errorMessage = null;
    _permissionPermanentlyDenied = false;
    
    try {
      // STEP 1: Load from storage super fast - this should be near-instant
      List<String> folderPaths = await _storageService.loadAudiobookFolders();
      _logDebug("Found ${folderPaths.length} cached audiobook paths");
      
      // SYNC DELETED AUDIOBOOKS: Check if folders still exist
      final List<String> validPaths = [];
      final List<String> deletedPaths = [];
      
      for (final path in folderPaths) {
        if (await Directory(path).exists()) {
          validPaths.add(path);
        } else {
          deletedPaths.add(path);
        }
      }
      
      // Handle deletions if any found
      if (deletedPaths.isNotEmpty) {
        _logDebug("Found ${deletedPaths.length} deleted audiobooks. Cleaning up...");
        for (final path in deletedPaths) {
          // The ID is the folder path
           await _storageService.removeAudiobookData(path);
           _logDebug("Cleaned up data for missing book: $path");
        }
        
        // Update the stored list of folders to reflect reality
        await _storageService.saveAudiobookFolders(validPaths);
        
        // Use the valid list for loading
        folderPaths = validPaths;
      }

      if (folderPaths.isEmpty) {
        // No audiobooks cached, show empty state immediately
        _audiobooks = [];
        notifyListeners();
        _logDebug("No cached audiobooks, showing empty library");
        return;
      }

      // STEP 2: Load basic info from cache super fast
      final List<Audiobook> loadedBooks = [];
      for (final path in folderPaths) {
        try {
          // Try to load from detailed cache first
          final cachedMetadata = await _storageService.loadCachedDetailedMetadata(path);
          if (cachedMetadata != null) {
            final cachedCoverArt = await _storageService.loadCachedCoverArt(path);
            final audiobook = _createAudiobookFromDetailedCache(path, cachedMetadata, cachedCoverArt);
            if (audiobook.chapters.isNotEmpty) {
              loadedBooks.add(audiobook);
              continue;
            }
          }
          
          // Fallback to basic cache
          final cachedBasicInfo = await _storageService.loadCachedBasicBookInfo(path);
          if (cachedBasicInfo != null) {
            final audiobook = _createAudiobookFromCachedInfo(path, cachedBasicInfo);
            if (audiobook.chapters.isNotEmpty) {
              loadedBooks.add(audiobook);
            }
          }
        } catch (e) {
          _logDebug("Error loading cached book $path: $e");
          // Skip this book but continue with others
        }
      }
      

    
      // STEP 3: Update UI with loaded books in the stored order initially
      
      // Load review data
      final reviewsMap = await _storageService.loadAudiobookReviews();
      
      // Update books with review data
      final booksWithReviews = loadedBooks.map((book) {
        final reviewData = reviewsMap[book.id];
        if (reviewData != null) {
          DateTime? timestamp;
          if (reviewData['timestamp'] != null) {
            timestamp = DateTime.tryParse(reviewData['timestamp'] as String);
          }
          return book.copyWith(
            rating: reviewData['rating'] != null ? (reviewData['rating'] as num).toDouble() : null,
            review: reviewData['review'] as String?,
            reviewTimestamp: timestamp,
          );
        }
        return book;
      }).toList();

      _audiobooks = booksWithReviews;
      await _loadLastPlayedTimestamps();
      
      // The stored order represents the last sorted order, so we preserve it
      // Sorting will be applied by the UI when the persistent sort preference is loaded
      _logDebug("Loaded ${loadedBooks.length} books in saved order");
      
      notifyListeners(); // Show UI immediately
      
      _logDebug("=== FAST STARTUP: UI displayed with ${loadedBooks.length} books ===");
      
      // STEP 4: Start background validation (no UI impact)
      unawaited(_validateLibraryInBackground());
      
    } catch (e, stackTrace) {
      _logDebug("Error in fast startup loading: $e\n$stackTrace");
      // Even on error, show empty state rather than loading
      _audiobooks = [];
      notifyListeners();
    }
  }
  
  /// Background validation of library without affecting UI
  Future<void> _validateLibraryInBackground() async {
    try {
      _logDebug("Starting background library validation...");
      
      // Only validate if we have permissions (don't request them)
      final hasPermissions = await _checkPermissionsQuietly();
      if (!hasPermissions) {
        _logDebug("Background validation skipped: no permissions");
        return;
      }
      
      final List<String> folderPaths = await _storageService.loadAudiobookFolders();
      bool anyChangesDetected = false;
      
      // Check each book path still exists
      for (final path in folderPaths) {
        final directory = Directory(path);
        if (!await directory.exists()) {
          // Try to find renamed folder
          final newPath = await _findRenamedFolder(path);
          if (newPath != null) {
            _logDebug("Background: Found renamed folder $path -> $newPath");
            await _handleFolderRename(path, newPath);
            anyChangesDetected = true;
          } else {
            // Remove missing book
            _logDebug("Background: Removing missing book $path");
            _audiobooks.removeWhere((book) => book.id == path);
            anyChangesDetected = true;
          }
        }
        
        // Small delay to keep system responsive
        await Future.delayed(const Duration(milliseconds: 10));
      }
      
      // Update UI if changes were detected
      if (anyChangesDetected) {
        await _storageService.saveAudiobookFolders(_audiobooks.map((b) => b.id).toList());
        _sortAudiobooksByStatus();
        notifyListeners();
        _logDebug("Background validation: UI updated due to changes");
      }
      
      _logDebug("Background library validation completed");
      
    } catch (e) {
      _logDebug("Error in background validation: $e");
    }
  }

  /// Proactively search for a renamed folder by checking parent directory
  Future<String?> _findRenamedFolder(String oldPath) async {
    try {
      // Get the parent directory
      final parentDir = Directory(oldPath).parent;
      if (!await parentDir.exists()) {
        return null;
      }

      // Get the old folder name for comparison
      final oldFolderName = oldPath.split(Platform.pathSeparator).last;
      _logDebug("🔍 Searching for renamed folder '$oldFolderName' in ${parentDir.path}");

      // Get content hash for the old audiobook to help identify it
      final targetHash = await _storageService.loadStoredContentHash(oldPath);
      
      // List all directories in the parent folder
      final entities = await parentDir.list().toList();
      final directories = entities.whereType<Directory>().toList();
      
      for (final dir in directories) {
        final dirName = dir.path.split(Platform.pathSeparator).last;
        
        // Skip if it's the exact same path
        if (dir.path == oldPath) continue;
        
        // Check if this directory contains audio files (quick check)
        if (await _containsAudioFiles(dir.path)) {
          // If we have a stored hash, verify it matches
          if (targetHash != null && targetHash.isNotEmpty) {
            final dirHash = await _storageService.generateContentHash(dir.path);
            if (dirHash == targetHash) {
              _logDebug("✅ Found renamed folder by content hash: ${dir.path}");
              return dir.path;
            }
          }
          
          // Fallback: Check for similar names or timing
          if (_isSimilarFolderName(oldFolderName, dirName)) {
            _logDebug("✅ Found likely renamed folder by name similarity: ${dir.path}");
            return dir.path;
          }
        }
      }
      
      _logDebug("❌ No renamed folder found for: $oldPath");
      return null;
    } catch (e) {
      _logDebug("Error finding renamed folder for $oldPath: $e");
      return null;
    }
  }

  /// Check if a directory contains audio files
  Future<bool> _containsAudioFiles(String dirPath) async {
    try {
      final directory = Directory(dirPath);
      final entities = await directory.list().toList();
      
      for (final entity in entities) {
        if (entity is File) {
          final extension = entity.path.split('.').last.toLowerCase();
          if (['mp3', 'm4a', 'm4b', 'wav', 'ogg', 'aac', 'flac'].contains(extension)) {
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Check if two folder names are similar (accounting for common rename patterns)
  bool _isSimilarFolderName(String oldName, String newName) {
    // Exact match
    if (oldName == newName) return false; // Same name, not a rename
    
    // Remove common prefixes/suffixes that users might add
    final cleanOld = oldName.toLowerCase()
        .replaceAll(RegExp(r'[\[\](){}]'), '') // Remove brackets
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize spaces
        .trim();
    
    final cleanNew = newName.toLowerCase()
        .replaceAll(RegExp(r'[\[\](){}]'), '') // Remove brackets
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize spaces
        .trim();
    
    // Check if one contains the other (accounting for added/removed words)
    if (cleanNew.contains(cleanOld) || cleanOld.contains(cleanNew)) {
      return true;
    }
    
    // Check for similar length and characters (fuzzy matching)
    if ((cleanOld.length - cleanNew.length).abs() <= 3) {
      int commonChars = 0;
      final shorter = cleanOld.length <= cleanNew.length ? cleanOld : cleanNew;
      final longer = cleanOld.length > cleanNew.length ? cleanOld : cleanNew;
      
      for (int i = 0; i < shorter.length; i++) {
        if (i < longer.length && shorter[i] == longer[i]) {
          commonChars++;
        }
      }
      
      // If more than 70% of characters match in order, consider it similar
      return (commonChars / shorter.length) > 0.7;
    }
    
    return false;
  }

  /// Handle folder rename by updating all references
  Future<void> _handleFolderRename(String oldPath, String newPath) async {
    try {
      // Find the audiobook with the old path
      final bookIndex = _audiobooks.indexWhere((book) => book.id == oldPath);
      if (bookIndex == -1) {
        _logDebug("Audiobook not found for path update: $oldPath");
        return;
      }
      
      final book = _audiobooks[bookIndex];
      
      // Create updated audiobook with new path
      final updatedBook = Audiobook(
        id: newPath,
        title: book.title,
        author: book.author,
        chapters: book.chapters.map((chapter) => Chapter(
          id: chapter.id.replaceFirst(oldPath, newPath),
          title: chapter.title,
          audiobookId: newPath,
          sourcePath: chapter.sourcePath.replaceFirst(oldPath, newPath),
          duration: chapter.duration,
          start: chapter.start,
          end: chapter.end,
        )).toList(),
        totalDuration: book.totalDuration,
        coverArt: book.coverArt,
        tags: book.tags,
        isFavorited: book.isFavorited,
      );
      
      // Update in the audiobooks list
      _audiobooks[bookIndex] = updatedBook;
      
      // Migrate all data to new path
      await _migrateAudiobookDataLegacy(oldPath, newPath);
      
      // Update stored content hash for future detection
      final contentHash = await _storageService.generateContentHash(newPath);
      await _storageService.updateContentHash(contentHash, newPath);
      
      _logDebug("✅ Successfully handled folder rename: $oldPath -> $newPath");
      
    } catch (e) {
      _logDebug("Error handling folder rename from $oldPath to $newPath: $e");
    }
  }

  /// Check if folder still exists and metadata is current
  Future<void> _syncBookInBackground(String folderPath) async {
    try {
      final directory = Directory(folderPath);
      
      // Check if folder was modified since last cache
      final stat = await directory.stat();
      final cachedBasicInfo = await _storageService.loadCachedBasicBookInfo(folderPath);
      
      if (cachedBasicInfo != null) {
        final cachedModified = cachedBasicInfo['folderModified'] as int?;
        if (cachedModified == stat.modified.millisecondsSinceEpoch) {
          // No changes needed
          return;
        }
      }
      
      // Folder was modified - update metadata in background
      _logDebug("Updating modified book: $folderPath");
      final updatedBook = await _metadataService.getAudiobookDetails(folderPath);
      
      if (updatedBook.chapters.isNotEmpty) {
        // Update the book in the list
        final index = _audiobooks.indexWhere((book) => book.id == folderPath);
        if (index != -1) {
          _audiobooks[index] = updatedBook;
          
          // Cache the updated metadata
          await _cacheBasicBookInfo(updatedBook, folderPath);
          await _cacheDetailedMetadata(updatedBook);
          
          // Update UI silently
          notifyListeners();
          _logDebug("Updated book metadata: ${updatedBook.title}");
        }
      }
      
    } catch (e) {
      _logDebug("Error syncing book $folderPath: $e");
    }
  }

  /// Check permissions quietly without requesting them
  Future<bool> _checkPermissionsQuietly() async {
    try {
      if (Platform.isAndroid) {
        DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        
        if (androidInfo.version.sdkInt >= 30) {
          // Android 11+ (API 30+)
          return await Permission.manageExternalStorage.isGranted;
        } else {
          // Android 10 and below
          return await Permission.storage.isGranted;
        }
      } else {
        // iOS or other platforms - assume granted
        return true;
      }
    } catch (e) {
      _logDebug("Error checking permissions quietly: $e");
      return false;
    }
  }
  
  /// Create audiobook from detailed cache (preferred method)
  Audiobook _createAudiobookFromDetailedCache(String path, Map<String, dynamic> metadata, Uint8List? coverArt) {
    try {
      final chaptersData = metadata['chapters'] as List<dynamic>? ?? [];
      final chapters = chaptersData.map((chapterData) {
        final data = chapterData as Map<String, dynamic>;
        return Chapter(
          id: data['id'] as String,
          title: data['title'] as String,
          audiobookId: path,
          sourcePath: data['sourcePath'] as String? ?? data['id'] as String,
          duration: Duration(milliseconds: data['durationMs'] as int? ?? 0),
          start: Duration(milliseconds: data['startMs'] as int? ?? 0),
          end: data['endMs'] != null ? Duration(milliseconds: data['endMs'] as int) : null,
        );
      }).toList().cast<Chapter>();

      return Audiobook(
        id: path,
        title: metadata['title'] as String? ?? p.basename(path),
        author: metadata['author'] as String?,
        chapters: chapters,
        totalDuration: Duration(milliseconds: metadata['totalDurationMs'] as int? ?? 0),
        coverArt: coverArt,
      );
    } catch (e) {
      _logDebug("Error creating audiobook from detailed cache: $e");
      return Audiobook(
        id: path,
        title: p.basename(path),
        author: null,
        chapters: [],
        totalDuration: Duration.zero,
      );
    }
  }

  /// Creates an Audiobook from cached basic info
  Audiobook _createAudiobookFromCachedInfo(String path, Map<String, dynamic> cachedInfo) {
    try {
      final chaptersData = cachedInfo['chapters'] as List<dynamic>? ?? [];
      final chapters = chaptersData.map((chapterData) {
        final data = chapterData as Map<String, dynamic>;
        return Chapter(
          id: data['id'] as String,
          title: data['title'] as String,
          audiobookId: path,
          sourcePath: data['sourcePath'] as String? ?? data['id'] as String,
          duration: Duration(milliseconds: data['durationMs'] as int? ?? 0),
          start: Duration(milliseconds: data['startMs'] as int? ?? 0),
          end: data['endMs'] != null ? Duration(milliseconds: data['endMs'] as int) : null,
        );
      }).toList().cast<Chapter>();

      return Audiobook(
        id: path,
        title: cachedInfo['title'] as String? ?? p.basename(path),
        author: cachedInfo['author'] as String?,
        chapters: chapters,
        totalDuration: Duration(milliseconds: cachedInfo['totalDurationMs'] as int? ?? 0),
        // coverArt will be loaded separately
      );
    } catch (e) {
      _logDebug("Error creating audiobook from cached info: $e");
      return Audiobook(
        id: path,
        title: p.basename(path),
        author: null,
        chapters: [],
        totalDuration: Duration.zero,
      );
    }
  }

  /// Cache basic book info for future quick loading
  Future<void> _cacheBasicBookInfo(Audiobook book, String folderPath) async {
    try {
      final directory = Directory(folderPath);
      final stat = await directory.stat();
      
      final basicInfo = {
        'title': book.title,
        'author': book.author,
        'chapterCount': book.chapters.length,
        'totalDurationMs': book.totalDuration.inMilliseconds,
        'folderModified': stat.modified.millisecondsSinceEpoch,
        'chapters': book.chapters.map((chapter) => {
          'id': chapter.id,
          'title': chapter.title,
          'sourcePath': chapter.sourcePath,
          'durationMs': chapter.duration?.inMilliseconds ?? 0,
          'startMs': chapter.start.inMilliseconds,
          'endMs': chapter.end?.inMilliseconds,
        }).toList(),
      };

      await _storageService.cacheBasicBookInfo(book.id, basicInfo);
    } catch (e) {
      _logDebug("Error caching basic book info for ${book.id}: $e");
    }
  }

  /// Cache detailed metadata
  Future<void> _cacheDetailedMetadata(Audiobook book) async {
    try {
      final metadata = {
        'title': book.title,
        'author': book.author,
        'totalDurationMs': book.totalDuration.inMilliseconds,
        'chapters': book.chapters.map((chapter) => {
          'id': chapter.id,
          'title': chapter.title,
          'sourcePath': chapter.sourcePath,
          'durationMs': chapter.duration?.inMilliseconds ?? 0,
          'startMs': chapter.start.inMilliseconds,
          'endMs': chapter.end?.inMilliseconds,
        }).toList(),
      };

      await _storageService.cacheDetailedMetadata(book.id, metadata);
      
      // Cache cover art separately if available
      if (book.coverArt != null) {
        await _storageService.saveCachedCoverArt(book.id, book.coverArt!);
      }
    } catch (e) {
      _logDebug("Error caching detailed metadata for ${book.id}: $e");
    }
  }

  /// Force refresh detailed metadata for a specific book
  Future<void> refreshBookMetadata(String audiobookId) async {
    final index = _audiobooks.indexWhere((book) => book.id == audiobookId);
    if (index == -1) return;

    try {
      final basicBook = _audiobooks[index];
      final detailedBook = await _metadataService.loadDetailedMetadata(basicBook);
      
      if (detailedBook.chapters.isNotEmpty) {
        _audiobooks[index] = detailedBook;
        await _cacheDetailedMetadata(detailedBook);
        notifyListeners();
        _logDebug("Refreshed metadata for: ${detailedBook.title}");
      }
    } catch (e) {
      _logDebug("Error refreshing metadata for $audiobookId: $e");
    }
  }


  /// Requests necessary storage/media permissions for adding new books
  Future<bool> _requestPermissions() async {
    PermissionStatus status;
    _permissionPermanentlyDenied = false; // Reset flag

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 30) {
        // Android 11+ (API 30+) needs "All Files Access" to see .nomedia folders
        // We request this instead of specific media permissions for maximum robustness
        status = await Permission.manageExternalStorage.request();
        
        // Also request notification for playback controls on Android 13+
        if (androidInfo.version.sdkInt >= 33) {
          await Permission.notification.request();
        }
      } else if (androidInfo.version.sdkInt >= 33) {
        // Fallback for API 33 if 30 branch was somehow skipped (impossible but safe)
        status = await Permission.audio.request();
        await Permission.notification.request();
      } else {
        // Older Android
        status = await Permission.storage.request();
      }
    } else {
      // Assume granted on other platforms for simplicity
      status = PermissionStatus.granted;
    }

    // Handle permission result
    if (status.isGranted) {
      _errorMessage = null; // Clear previous errors
      _logDebug("Storage/Media permissions granted.");
      return true;
    } else if (status.isPermanentlyDenied) {
      _errorMessage = "Permission permanently denied. Please enable Storage/Media access in App Settings to scan for books.";
      _permissionPermanentlyDenied = true;
      _logDebug("Storage/Media permissions permanently denied.");
      notifyListeners();
      return false;
    } else {
      _errorMessage = "Storage/Media permission is required to access audiobooks.";
      _logDebug("Storage/Media permissions denied.");
      notifyListeners();
      return false;
    }
  }

  /// Add audiobooks with seamless background processing
  Future<void> addAudiobooksRecursively() async {
    _startLoading();
    _errorMessage = null;
    
    // Show loading screen immediately
    notifyListeners();
    
    if (!await _requestPermissions()) {
      _stopLoading();
      return;
    }

    try {
      // Use file picker to select the root directory
      String? rootDirectoryPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Audiobooks Root Folder - Will scan all subfolders',
        lockParentWindow: true,
      );

      if (rootDirectoryPath != null && rootDirectoryPath.isNotEmpty) {
        _logDebug("Root audiobooks folder selected: $rootDirectoryPath");

        // Store the root path for auto-tag creation
        _lastScannedRootPath = rootDirectoryPath;

        // Start processing immediately with proper error handling
        await _processNewBooksInBackground(rootDirectoryPath);

      } else {
        _logDebug("Folder selection cancelled or resulted in null/empty path.");
        _stopLoading();
      }
    } catch (e, stackTrace) {
      _logDebug("Error during addAudiobooksRecursively process: $e\n$stackTrace");
      _errorMessage = "An error occurred while accessing the file system: $e";
      _stopLoading();
    }
  }

  /// Process new books in background without blocking UI
  Future<void> _processNewBooksInBackground(String rootDirectoryPath) async {
    try {
      // Note: Loading already started in addAudiobooksRecursively - no need to call _startLoading() again
      
      final List<String> discoveredFolders = 
          await _metadataService.scanForAudiobookFolders(rootDirectoryPath);

      if (discoveredFolders.isEmpty) {
        _logDebug("CRITICAL: Stopping loading - no folders found");
        _stopLoading();
        _errorMessage = 
            "No audiobook folders found in the selected directory.\n\n"
            "Make sure your audiobooks are in folders containing audio files:\n"
            "• MP3, M4A, M4B, WAV, OGG, AAC, FLAC\n\n"
            "The scanner looks for folders with audio files at any depth in your folder structure.";
        _logDebug("No audiobook folders discovered in: $rootDirectoryPath");
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Filter out already existing books to get actual workload
      final newFolders = discoveredFolders.where((folderPath) => 
        !_audiobooks.any((book) => book.id == folderPath)).toList();
      
      if (newFolders.isEmpty) {
        _logDebug("CRITICAL: Stopping loading - all books already exist");
        _stopLoading();
        _errorMessage = "All audiobooks in this directory are already in your library.";
        _isLoading = false;
        notifyListeners();
        return;
      }

      _logDebug("Found ${discoveredFolders.length} potential audiobook folders (${newFolders.length} new)");
      int successCount = 0;
      int skipCount = 0;
      final List<String> newlyAddedPaths = [];
      
      // Process each new audiobook folder
      for (int i = 0; i < newFolders.length; i++) {
        final folderPath = newFolders[i];
        final fileName = folderPath.split('/').last;
        
        try {
          // Get audiobook details for this folder
          final newBook = await _metadataService.getAudiobookDetails(folderPath);

          if (newBook.chapters.isEmpty) {
            _logDebug("No valid chapters found in: $folderPath");
            skipCount++;
          } else {
            
            // Mark the new book as "new" (never played)
            _newBooks[newBook.id] = true;
            _lastPlayedTimestamps[newBook.id] = 0;
            _completedBooks[newBook.id] = false;

            _audiobooks.add(newBook);
            // Sort using current sort preference when adding new books
            _sortAudiobooksByStatus();
            newlyAddedPaths.add(folderPath);
            successCount++;
            
            // Cache the new book metadata
            await _cacheBasicBookInfo(newBook, folderPath);
            await _cacheDetailedMetadata(newBook);
            
            // Register with file tracking system 🐛
            await _storageService.registerAudiobook(
              folderPath,
              title: newBook.title,
              author: newBook.author,
              chapterCount: newBook.chapters.length,
            );
            
            // Store content hash for future rename detection
            final contentHash = await _storageService.generateContentHash(folderPath);
            await _storageService.updateContentHash(contentHash, folderPath);
          }
        } catch (e) {
          _logDebug("Error processing folder $folderPath: $e");
          skipCount++;
        }
      }

      // Store the newly added paths for auto-tag creation
      _lastAddedPaths = newlyAddedPaths;

      // Save the updated audiobook folders list
      await _storageService.saveAudiobookFolders(_audiobooks.map((book) => book.id).toList());

      // CRITICAL FIX: Force stop loading before any additional processing
      _logDebug("CRITICAL: Force stopping loading after main processing complete");
      _forceStopLoading();

      _logDebug("Background processing complete: $successCount added, $skipCount skipped");
      
    } catch (e) {
      _logDebug("Error in background processing: $e");
      _logDebug("CRITICAL: Stopping loading due to error");
      _forceStopLoading();
      _errorMessage = "Error processing audiobooks: $e";
    }
  }

  /// Add single audiobook folder
  Future<void> addAudiobookFolder() async {
    if (!await _requestPermissions()) {
      return;
    }

    try {
      // Start loading and show immediately
      _startLoading();
      
      // Show loading screen immediately
      notifyListeners();
      
      // Use FilePicker to select a single directory path
      String? selectedDirectoryPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Single Audiobook Folder',
        lockParentWindow: true,
      );

      if (selectedDirectoryPath != null && selectedDirectoryPath.isNotEmpty) {
        _logDebug("Single audiobook folder selected: $selectedDirectoryPath");

        // Check if this exact path is already in the library
        if (_audiobooks.any((book) => book.id == selectedDirectoryPath)) {
          _stopLoading();
          _errorMessage = "This audiobook folder is already in your library.";
          _logDebug("Attempted to add duplicate folder: $selectedDirectoryPath");
          notifyListeners();
          return;
        }

        // Process in background
        unawaited(_processSingleBookInBackground(selectedDirectoryPath));

      } else {
        _logDebug("Single folder selection cancelled.");
        _stopLoading();
      }
    } catch (e, stackTrace) {
      _logDebug("Error during addAudiobookFolder process: $e\n$stackTrace");
      _errorMessage = "An error occurred while accessing the file system.";
      _stopLoading();
    }
  }

  /// Process single book in background
  Future<void> _processSingleBookInBackground(String selectedDirectoryPath) async {
    try {
      // Note: Loading already started in addAudiobookFolder - no need to call _startLoading() again
      
      // Get audiobook details for the selected path
      final newBook = await _metadataService.getAudiobookDetails(selectedDirectoryPath);

      if (newBook.chapters.isEmpty) {
        _stopLoading();
        _errorMessage =
            "The selected folder contains no compatible audio files.\n\n"
            "Supported formats: MP3, M4A, M4B, WAV, OGG, AAC, FLAC\n\n"
            "Please select a folder that contains audio files, or use "
            "'Add Multiple Books' to scan for audiobooks in subfolders.";
        _logDebug("No compatible chapters found in: $selectedDirectoryPath");
        notifyListeners();
      } else {
        
        // Mark the new book as "new" (never played)
        _newBooks[newBook.id] = true;
        _lastPlayedTimestamps[newBook.id] = 0;
        _completedBooks[newBook.id] = false;

        _audiobooks.add(newBook);
        // Sort using current sort preference when adding new books
        _sortAudiobooksByStatus();

        // Cache the new book
        await _cacheBasicBookInfo(newBook, selectedDirectoryPath);
        await _cacheDetailedMetadata(newBook);
        
        // Register with file tracking system 🐛
        await _storageService.registerAudiobook(
          selectedDirectoryPath,
          title: newBook.title,
          author: newBook.author,
          chapterCount: newBook.chapters.length,
        );

        // Store content hash for future rename detection
        final contentHash = await _storageService.generateContentHash(selectedDirectoryPath);
        await _storageService.updateContentHash(contentHash, selectedDirectoryPath);

        // Save the updated list of folder paths
        await _storageService.saveAudiobookFolders(
          _audiobooks.map((b) => b.id).toList(),
        );

        // Store info for potential auto-tag creation from UI
        _lastScannedRootPath = Directory(selectedDirectoryPath).parent.path;
        _lastAddedPaths = [selectedDirectoryPath];
        _logDebug("Single audiobook added and ready for auto-tagging");
        
        _forceStopLoading();
        _errorMessage = null;
        _logDebug("Successfully added audiobook: ${newBook.title} with ${newBook.chapters.length} chapters");
      }
    } catch (e, stackTrace) {
      _forceStopLoading();
      
          _logDebug("Error processing single audiobook folder: $e\n$stackTrace");
          _errorMessage = 
              "Failed to process the selected folder. The folder may be corrupted "
              "or contain unsupported file formats.";
    }
  }

  /// Legacy method - now redirects to the new recursive method
  Future<void> addMultipleAudiobooks() async {
    await addAudiobooksRecursively();
  }

  /// Removes an audiobook from the library and cleans up all associated data
  Future<void> removeAudiobook(String audiobookId, WidgetRef ref) async {
    try {
      // Remove the audiobook from the list
      _audiobooks.removeWhere((audiobook) => audiobook.id == audiobookId);
      
      // Clean up all stored data for this audiobook
      await _storageService.removeAudiobookData(audiobookId);
      
      // Remove custom title if exists
      _customTitles.remove(audiobookId);
      await _saveCustomTitles();

      // Remove from completed books tracking
      _completedBooks.remove(audiobookId);

      // Remove from new books tracking
      _newBooks.remove(audiobookId);
      
      // Remove from last played timestamps
      _lastPlayedTimestamps.remove(audiobookId);
      
      // Clean up tag associations
      final audiobookTagsNotifier = ref.read(audiobookTagsProvider.notifier);
      await audiobookTagsNotifier.removeAllTagsFromAudiobook(audiobookId);
      
      // Recalculate tag counts after removal and clean up orphaned tags
      final currentAudiobookTags = ref.read(audiobookTagsProvider);
      await ref.read(tagProvider.notifier).recalculateTagCountsWithCleanup(currentAudiobookTags, cleanupOrphaned: false);
      
      notifyListeners();
      _logDebug("Successfully removed audiobook: $audiobookId");
      
    } catch (e) {
      _logDebug("Error removing audiobook $audiobookId: $e");
      rethrow;
    }
  }

  /// Updates an audiobook's ID when its path changes (renames/moves)
  Future<void> updateAudiobookId(String oldId, String newId, WidgetRef ref) async {
    try {
      // Find the audiobook with the old ID
      final audiobookIndex = _audiobooks.indexWhere((book) => book.id == oldId);
      if (audiobookIndex == -1) {
        _logDebug("Audiobook with ID $oldId not found for update");
        return;
      }
      
      // Update the audiobook's ID (this might require creating a new Audiobook instance)
      final oldAudiobook = _audiobooks[audiobookIndex];
      final updatedAudiobook = Audiobook(
        id: newId,
        title: oldAudiobook.title,
        author: oldAudiobook.author,
        chapters: oldAudiobook.chapters,
        totalDuration: oldAudiobook.totalDuration,
        coverArt: oldAudiobook.coverArt,
        tags: oldAudiobook.tags,
        isFavorited: oldAudiobook.isFavorited,
        rating: oldAudiobook.rating,
        review: oldAudiobook.review,
        reviewTimestamp: oldAudiobook.reviewTimestamp,
      );
      
      _audiobooks[audiobookIndex] = updatedAudiobook;
      
      // Update custom title mapping
      if (_customTitles.containsKey(oldId)) {
        _customTitles[newId] = _customTitles[oldId]!;
        _customTitles.remove(oldId);
        await _saveCustomTitles();
      }
      
      // Update completed books tracking
      if (_completedBooks.containsKey(oldId)) {
        _completedBooks[newId] = _completedBooks[oldId]!;
        _completedBooks.remove(oldId);
      }
      
      // Update new books tracking
      if (_newBooks.containsKey(oldId)) {
        _newBooks[newId] = _newBooks[oldId]!;
        _newBooks.remove(oldId);
      }
      
      // Update last played timestamps
      if (_lastPlayedTimestamps.containsKey(oldId)) {
        _lastPlayedTimestamps[newId] = _lastPlayedTimestamps[oldId]!;
        _lastPlayedTimestamps.remove(oldId);
      }
      
      // Update stored audiobook data with new ID
      await _storageService.updateAudiobookId(oldId, newId);
      
      // Update tag associations
      final audiobookTagsNotifier = ref.read(audiobookTagsProvider.notifier);
      await audiobookTagsNotifier.updateAudiobookId(oldId, newId);
      
      notifyListeners();
      _logDebug("Successfully updated audiobook ID from $oldId to $newId");
      
    } catch (e) {
      _logDebug("Error updating audiobook ID from $oldId to $newId: $e");
      rethrow;
    }
  }

  /// Opens the app's settings screen using permission_handler.
  Future<void> openSettings() async {
    _logDebug("Opening app settings...");
    await openAppSettings();
  }

  /// Legacy migration method for path changes (does not update tags)
  /// Note: Tag associations need to be updated separately using updateAudiobookId
  Future<void> _migrateAudiobookDataLegacy(String oldPath, String newPath) async {
    try {
      // Migrate last played timestamps
      if (_lastPlayedTimestamps.containsKey(oldPath)) {
        _lastPlayedTimestamps[newPath] = _lastPlayedTimestamps[oldPath]!;
        _lastPlayedTimestamps.remove(oldPath);
      }
      
      // Migrate completion status
      if (_completedBooks.containsKey(oldPath)) {
        _completedBooks[newPath] = _completedBooks[oldPath]!;
        _completedBooks.remove(oldPath);
      }
      
      // Migrate new book status
      if (_newBooks.containsKey(oldPath)) {
        _newBooks[newPath] = _newBooks[oldPath]!;
        _newBooks.remove(oldPath);
      }
      
      // Migrate custom titles
      if (_customTitles.containsKey(oldPath)) {
        _customTitles[newPath] = _customTitles[oldPath]!;
        _customTitles.remove(oldPath);
        await _saveCustomTitles();
      }
      
      // Migrate storage service data
      await _storageService.updateAudiobookId(oldPath, newPath);
      
      _logDebug("Migrated audiobook data: $oldPath -> $newPath (Note: tags need separate update)");
      
    } catch (e) {
      _logDebug("Error migrating audiobook data: $e");
    }
  }

  /// Performs comprehensive library sync with tag updates
  /// Call this from UI components when you need full synchronization including tags
  Future<void> performComprehensiveSync(WidgetRef ref) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      final folderPaths = await _storageService.loadAudiobookFolders();
      final List<String> pathsToRemove = [];
      final Map<String, String> pathMigrations = {};
      
      // Check each book for path changes or deletions
      for (final folderPath in folderPaths) {
        final directory = Directory(folderPath);
        
        if (!await directory.exists()) {
          // Try to find the book in a new location using file tracking
          final newPath = await _storageService.findMigratedPath(folderPath);
          
          if (newPath != null) {
            // Book found in new location - prepare for migration
            pathMigrations[folderPath] = newPath;
            _logDebug("Found book moved from $folderPath to $newPath");
          } else {
            // Book is truly missing - mark for removal
            pathsToRemove.add(folderPath);
            _logDebug("Book not found, marking for removal: $folderPath");
          }
        }
      }
      
      // Handle path migrations with tag updates
      for (final migration in pathMigrations.entries) {
        final oldPath = migration.key;
        final newPath = migration.value;
        
        try {
          // Use the comprehensive update method that includes tags
          await updateAudiobookId(oldPath, newPath, ref);
          _logDebug("Successfully migrated book with tags: $oldPath -> $newPath");
        } catch (e) {
          _logDebug("Error migrating book with tags $oldPath -> $newPath: $e");
          // Fallback to legacy migration if comprehensive fails
          await _migrateAudiobookDataLegacy(oldPath, newPath);
        }
      }
      
      // Handle book removals with tag cleanup
      for (final pathToRemove in pathsToRemove) {
        try {
          await removeAudiobook(pathToRemove, ref);
          _logDebug("Successfully removed missing book with tag cleanup: $pathToRemove");
        } catch (e) {
          _logDebug("Error removing missing book $pathToRemove: $e");
          // Fallback to simple removal
          _audiobooks.removeWhere((book) => book.id == pathToRemove);
        }
      }
      
      // Final tag count recalculation
      final currentAudiobookTags = ref.read(audiobookTagsProvider);
      await ref.read(tagProvider.notifier).recalculateTagCountsWithCleanup(currentAudiobookTags, cleanupOrphaned: false);
      
      _isLoading = false;
      notifyListeners();
      
      _logDebug("Comprehensive sync completed: ${pathMigrations.length} migrations, ${pathsToRemove.length} removals");
      
    } catch (e) {
      _logDebug("Error in comprehensive sync: $e");
      _isLoading = false;
      _errorMessage = "Error during library synchronization: $e";
      notifyListeners();
    }
  }

  /// Forces a complete re-scan of the library by clearing metadata caches
  /// and re-examining all added folder paths.
  Future<void> forceRefreshLibrary() async {
    try {
      _startLoading();
      _logDebug("Starting DEEP RESCAN of the library...");
      
      // 1. Clear all metadata and cover art caches
      await _storageService.clearAllBookMetadataCache();
      
      // 2. Load existing folder paths
      final folderPaths = await _storageService.loadAudiobookFolders();
      
      if (folderPaths.isEmpty) {
        _logDebug("Deep rescan: No folders to rescan.");
        _stopLoading();
        return;
      }
      
      // 3. Clear existing in-memory list so we don't have duplicates
      _audiobooks = [];
      notifyListeners();
      
      // 4. Re-scan each folder thoroughly
      for (final folderPath in folderPaths) {
        if (await Directory(folderPath).exists()) {
          _logDebug("Deep rescan: Processing $folderPath");
          try {
            // This will use fresh metadata because we cleared the cache above
            final newBook = await _metadataService.getAudiobookDetails(folderPath);
            
            if (newBook.chapters.isNotEmpty) {
              _audiobooks.add(newBook);
              // Cache immediately
              await _cacheBasicBookInfo(newBook, folderPath);
              await _cacheDetailedMetadata(newBook);
            }
          } catch (e) {
            _logDebug("Error rescanning folder $folderPath: $e");
          }
        } else {
          _logDebug("Deep rescan: Skipping non-existent folder $folderPath");
        }
      }
      
      // 5. Final sort and save
      _sortAudiobooksByStatus();
      await _storageService.saveAudiobookFolders(_audiobooks.map((b) => b.id).toList());
      
      _stopLoading();
      _logDebug("DEEP RESCAN completed successfully.");
      
    } catch (e) {
      _logDebug("Error during deep rescan: $e");
      _stopLoading();
      _errorMessage = "An error occurred during deep rescan: $e";
      notifyListeners();
    }
  }

  /// Scans existing library books and creates auto-tags based on folder structure
  /// This helps users who deleted tags or upgraded from previous versions
  Future<void> scanExistingLibraryForTags(WidgetRef ref) async {
    try {
      _logDebug("Starting existing library scan for auto-tags...");
      
      if (_audiobooks.isEmpty) {
        _logDebug("No audiobooks in library to scan for tags");
        return;
      }

      // Get all existing audiobook paths
      final existingPaths = _audiobooks.map((book) => book.id).toList();
      _logDebug("Scanning ${existingPaths.length} existing audiobooks for potential tags");

      // Find common root paths to use for tag suggestions
      final rootPaths = _findCommonRootPaths(existingPaths);
      _logDebug("Found ${rootPaths.length} common root paths: ${rootPaths.join(', ')}");

      int totalTagsCreated = 0;
      int totalAssignments = 0;
      final Set<String> allCreatedTags = {};
      final Set<String> allExistingTags = {};

      // Process each root path separately for better tag organization
      for (final rootPath in rootPaths) {
        final booksInRoot = existingPaths.where((path) => path.startsWith(rootPath)).toList();
        
        if (booksInRoot.length < 2) {
          _logDebug("Skipping root '$rootPath' - only ${booksInRoot.length} book(s)");
          continue; // Need at least 2 books to create meaningful tags
        }

        _logDebug("Processing ${booksInRoot.length} books under root: $rootPath");

        // Create auto-tags for this group of books
        final autoTagService = AutoTagService(ref);
        final result = await autoTagService.createAutoTagsForAudiobooks(
          audiobookPaths: booksInRoot,
          rootPath: rootPath,
          createTags: true,
          assignTags: true,
        );

        // Accumulate results
        totalTagsCreated += result.createdTags.length;
        totalAssignments += result.totalAssignments;
        allCreatedTags.addAll(result.createdTags);
        allExistingTags.addAll(result.existingTags);

        _logDebug("Root '$rootPath' results: ${result.createdTags.length} new tags, ${result.totalAssignments} assignments");
      }

      // Final summary
      _logDebug("🎯 Existing library scan completed:");
      _logDebug("  ✅ Total new tags created: $totalTagsCreated");
      _logDebug("  🔄 Total existing tags used: ${allExistingTags.length}");
      _logDebug("  📚 Total tag assignments: $totalAssignments");
      
      if (allCreatedTags.isNotEmpty) {
        _logDebug("  🏷️ New tags: ${allCreatedTags.join(', ')}");
      }

    } catch (e) {
      _logDebug("Error scanning existing library for tags: $e");
      rethrow;
    }
  }

  /// Finds common root paths from a list of audiobook paths
  /// This helps group books by their folder structure for better tag organization
  List<String> _findCommonRootPaths(List<String> paths) {
    if (paths.isEmpty) return [];
    if (paths.length == 1) return [Directory(paths.first).parent.path];

    final rootPaths = <String>{};

    // For each path, try different levels of parent directories
    for (final path in paths) {
      Directory current = Directory(path);
      final pathSegments = path.split(Platform.pathSeparator);
      
      // Try up to 3 levels up from the audiobook folder
      for (int levelsUp = 1; levelsUp <= 3 && current.parent.path != current.path; levelsUp++) {
        current = current.parent;
        
        // Count how many paths share this root
        final booksUnderRoot = paths.where((p) => p.startsWith(current.path)).length;
        
        // If at least 2 books share this root, it's a candidate
        if (booksUnderRoot >= 2) {
          rootPaths.add(current.path);
        }
      }
    }

    // Sort by depth (deeper first) to prefer more specific groupings
    final sortedRoots = rootPaths.toList();
    sortedRoots.sort((a, b) {
      final aDepth = a.split(Platform.pathSeparator).length;
      final bDepth = b.split(Platform.pathSeparator).length;
      return bDepth.compareTo(aDepth); // Deeper first
    });

    // Remove redundant roots (if a deeper root covers the same books as a shallower one)
    final finalRoots = <String>[];
    for (final root in sortedRoots) {
      final booksInRoot = paths.where((p) => p.startsWith(root)).toSet();
      
      // Check if any existing final root already covers all these books
      bool alreadyCovered = false;
      for (final existingRoot in finalRoots) {
        final booksInExisting = paths.where((p) => p.startsWith(existingRoot)).toSet();
        if (booksInRoot.difference(booksInExisting).isEmpty) {
          alreadyCovered = true;
          break;
        }
      }
      
      if (!alreadyCovered) {
        finalRoots.add(root);
      }
    }

    return finalRoots.isNotEmpty ? finalRoots : [Directory(paths.first).parent.path];
  }


}

