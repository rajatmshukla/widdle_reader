import 'dart:io'; // For Platform and Directory
import 'dart:async'; // For unawaited
import 'dart:typed_data'; // For Uint8List
import 'package:flutter/foundation.dart'; // For debugPrint and ChangeNotifier
import 'package:permission_handler/permission_handler.dart'; // For permissions
import 'package:file_picker/file_picker.dart'; // For picking folders
import 'package:device_info_plus/device_info_plus.dart'; // For Android version check
import 'package:flutter_riverpod/flutter_riverpod.dart'; // For WidgetRef
import 'package:path/path.dart' as p; // For path operations
// import 'package:shared_preferences/shared_preferences.dart'; // For SharedPreferences - not needed directly

// Import local models and services
import '../models/audiobook.dart';
import '../models/chapter.dart';
import '../models/tag.dart';
import '../services/metadata_service.dart';
import '../services/storage_service.dart';
import '../services/auto_tag_service.dart';


class AudiobookProvider extends ChangeNotifier {
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

  // Getters for state
  List<Audiobook> get audiobooks => _audiobooks;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get permissionPermanentlyDenied => _permissionPermanentlyDenied;

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
    _loadCustomTitles().then((_) => loadAudiobooks());
  }

  /// Loads saved custom titles from preferences
  Future<void> _loadCustomTitles() async {
    try {
      final savedTitles = await _storageService.loadCustomTitles();
      _customTitles.clear();
      _customTitles.addAll(savedTitles);
      debugPrint("Loaded ${_customTitles.length} custom titles");
    } catch (e) {
      debugPrint("Error loading custom titles: $e");
    }
  }

  /// Saves custom titles to preferences
  Future<void> _saveCustomTitles() async {
    try {
      await _storageService.saveCustomTitles(_customTitles);
      debugPrint("Saved ${_customTitles.length} custom titles");
    } catch (e) {
      debugPrint("Error saving custom titles: $e");
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

  // Method to refresh UI without reloading audiobooks
  void refreshUI() {
    notifyListeners();
  }

  /// Clears any error messages
  void clearErrorMessage() {
    _errorMessage = null;
    notifyListeners();
  }

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

  /// Sorts audiobooks with completed books at the bottom and others by recently played
  void _sortAudiobooksByStatus() {
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

      // Most recent first (descending order)
      return bTimestamp.compareTo(aTimestamp);
    });
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
      debugPrint("Starting auto-tag creation for ${audiobookPaths.length} audiobooks");
      
      final autoTagService = AutoTagService(ref);
      final result = await autoTagService.createAutoTagsForAudiobooks(
        audiobookPaths: audiobookPaths,
        rootPath: rootPath,
        createTags: true,
        assignTags: true,
      );
      
      if (result.hasSuccess) {
        debugPrint("Auto-tag creation successful: ${result.summary}");
        
        // Update error message to show success
        _errorMessage = null;
        
        // Show success message in debug log
        if (result.createdTags.isNotEmpty) {
          debugPrint("Created tags: ${result.createdTags.join(', ')}");
        }
        if (result.totalAssignments > 0) {
          debugPrint("Made ${result.totalAssignments} tag assignments");
        }
        
      } else if (result.hasError) {
        debugPrint("Auto-tag creation failed: ${result.error}");
      } else {
        debugPrint("No auto-tags created (no suitable folder structure found)");
      }
      
    } catch (e) {
      debugPrint("Error in auto-tag creation: $e");
    }
  }

  /// Creates and assigns auto-tags for a single audiobook
  Future<void> createAutoTagsForSingleBook(
    String audiobookPath, 
    String rootPath,
    WidgetRef ref
  ) async {
    try {
      debugPrint("Creating auto-tags for single audiobook: $audiobookPath");
      
      final autoTagService = AutoTagService(ref);
      final result = await autoTagService.createAutoTagsForSingleAudiobook(
        audiobookPath: audiobookPath,
        rootPath: rootPath,
        createTags: true,
        assignTags: true,
      );
      
      if (result.hasSuccess) {
        debugPrint("Auto-tag creation for single book successful: ${result.summary}");
      } else if (result.hasError) {
        debugPrint("Auto-tag creation for single book failed: ${result.error}");
      } else {
        debugPrint("No auto-tags created for single book");
      }
      
    } catch (e) {
      debugPrint("Error creating auto-tags for single book: $e");
    }
  }

  /// SEAMLESS APPROACH: Instant loading from cache with invisible background sync
  /// App opens immediately with cached data, background sync happens transparently
  Future<void> loadAudiobooks() async {
    // Never show loading state - use cached data immediately
    _isLoading = false;
    _errorMessage = null;
    _permissionPermanentlyDenied = false;
    
    try {
      // STEP 1: Instantly load cached audiobooks (no delay, no loading state)
      await _loadCachedAudiobooksInstantly();
      
      // STEP 2: Start invisible background sync (user doesn't see this)
      unawaited(_performInvisibleBackgroundSync());
      
    } catch (e, stackTrace) {
      debugPrint("Error in seamless loading: $e\n$stackTrace");
      // Even on error, don't show loading - try to show what we have cached
      await _loadCachedAudiobooksInstantly();
    }
  }
  
  /// Load all cached audiobooks instantly without any loading indicators
  Future<void> _loadCachedAudiobooksInstantly() async {
    try {
      // Get saved folder paths
      final List<String> folderPaths = await _storageService.loadAudiobookFolders();
      final List<Audiobook> cachedBooks = [];
      
      // Load all cached audiobooks at once (this should be very fast)
      for (final path in folderPaths) {
        try {
          // Try detailed metadata cache first
          final cachedMetadata = await _storageService.loadCachedDetailedMetadata(path);
          final cachedCoverArt = await _storageService.loadCachedCoverArt(path);
          
          if (cachedMetadata != null) {
            // Create full audiobook from cache
            final audiobook = _createAudiobookFromDetailedCache(path, cachedMetadata, cachedCoverArt);
            if (audiobook.chapters.isNotEmpty) {
              cachedBooks.add(audiobook);
              continue;
            }
          }
          
          // Fallback to basic cache
          final cachedBasicInfo = await _storageService.loadCachedBasicBookInfo(path);
          if (cachedBasicInfo != null) {
            final audiobook = _createAudiobookFromCachedInfo(path, cachedBasicInfo);
            if (audiobook.chapters.isNotEmpty) {
              cachedBooks.add(audiobook);
            }
          }
        } catch (e) {
          debugPrint("Error loading cached audiobook $path: $e");
          // Skip this book but continue with others
        }
      }
      
      // Update UI immediately with cached books
      _audiobooks = cachedBooks;
      await _loadLastPlayedTimestamps();
      notifyListeners(); // UI shows instantly
      
      debugPrint("Instant load complete: ${cachedBooks.length} audiobooks from cache");
      
    } catch (e) {
      debugPrint("Error loading cached audiobooks: $e");
      // Even on error, try to show empty state rather than loading
      _audiobooks = [];
      notifyListeners();
    }
  }
  
  /// Invisible background sync - no UI changes, no loading indicators
  Future<void> _performInvisibleBackgroundSync() async {
    try {
      // Only sync if we have permissions (don't request them, just check)
      final hasPermissions = await _checkPermissionsQuietly();
      if (!hasPermissions) {
        debugPrint("Background sync skipped: no permissions");
        return;
      }
      
      debugPrint("Starting invisible background sync...");
      
      // Get current folder paths
      final List<String> folderPaths = await _storageService.loadAudiobookFolders();
      
      // Check each book in background
      for (final path in folderPaths) {
        try {
          await _syncBookInBackground(path);
          // Small delay to keep system responsive
          await Future.delayed(const Duration(milliseconds: 50));
        } catch (e) {
          debugPrint("Error syncing book $path in background: $e");
          // Continue with other books
        }
      }
      
      debugPrint("Background sync completed");
      
    } catch (e) {
      debugPrint("Error in background sync: $e");
    }
  }
  
  /// Check if folder still exists and metadata is current
  Future<void> _syncBookInBackground(String folderPath) async {
    try {
      final directory = Directory(folderPath);
      if (!await directory.exists()) {
        // Book folder was deleted - remove from library silently
        _audiobooks.removeWhere((book) => book.id == folderPath);
        await _storageService.saveAudiobookFolders(_audiobooks.map((b) => b.id).toList());
        notifyListeners(); // Update UI to remove deleted book
        debugPrint("Removed deleted book: $folderPath");
        return;
      }
      
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
      debugPrint("Updating modified book: $folderPath");
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
          debugPrint("Updated book metadata: ${updatedBook.title}");
        }
      }
      
    } catch (e) {
      debugPrint("Error syncing book $folderPath: $e");
    }
  }
  
  /// Check permissions without requesting them
  Future<bool> _checkPermissionsQuietly() async {
    try {
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        
        if (androidInfo.version.sdkInt >= 33) {
          // Android 13+ - check for specific permissions
          final audioPermission = await Permission.audio.status;
          return audioPermission.isGranted;
        } else {
          // Android 12 and below - check storage permission
          final storagePermission = await Permission.storage.status;
          return storagePermission.isGranted;
        }
      }
      return true; // Assume granted on other platforms
    } catch (e) {
      debugPrint("Error checking permissions: $e");
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
          duration: Duration(milliseconds: data['durationMs'] as int? ?? 0),
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
      debugPrint("Error creating audiobook from detailed cache: $e");
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
          duration: Duration(milliseconds: data['durationMs'] as int? ?? 0),
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
      debugPrint("Error creating audiobook from cached info: $e");
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
          'durationMs': chapter.duration?.inMilliseconds ?? 0,
        }).toList(),
      };

      await _storageService.cacheBasicBookInfo(book.id, basicInfo);
    } catch (e) {
      debugPrint("Error caching basic book info for ${book.id}: $e");
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
          'durationMs': chapter.duration?.inMilliseconds ?? 0,
        }).toList(),
      };

      await _storageService.cacheDetailedMetadata(book.id, metadata);
      
      // Cache cover art separately if available
      if (book.coverArt != null) {
        await _storageService.cacheCoverArt(book.id, book.coverArt!);
      }
    } catch (e) {
      debugPrint("Error caching detailed metadata for ${book.id}: $e");
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
        debugPrint("Refreshed metadata for: ${detailedBook.title}");
      }
    } catch (e) {
      debugPrint("Error refreshing metadata for $audiobookId: $e");
    }
  }

  /// Requests necessary storage/media permissions for adding new books
  Future<bool> _requestPermissions() async {
    PermissionStatus status;
    _permissionPermanentlyDenied = false; // Reset flag

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        // Android 13+
        status = await Permission.audio.request();
        await Permission.notification.request(); // Request notification permission too
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
      debugPrint("Storage/Media permissions granted.");
      return true;
    } else if (status.isPermanentlyDenied) {
      _errorMessage = "Permission denied. Please enable Storage/Media access in app settings.";
      _permissionPermanentlyDenied = true;
      debugPrint("Storage/Media permissions permanently denied.");
      notifyListeners();
      return false;
    } else {
      _errorMessage = "Storage/Media permission is required to access audiobooks.";
      debugPrint("Storage/Media permissions denied.");
      notifyListeners();
      return false;
    }
  }

  /// Add audiobooks with seamless background processing
  Future<void> addAudiobooksRecursively() async {
    if (!await _requestPermissions()) {
      return;
    }

    try {
      // Use file picker to select the root directory
      String? rootDirectoryPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Audiobooks Root Folder - Will scan all subfolders',
        lockParentWindow: true,
      );

      if (rootDirectoryPath != null && rootDirectoryPath.isNotEmpty) {
        debugPrint("Root audiobooks folder selected: $rootDirectoryPath");

        // Store the root path for auto-tag creation
        _lastScannedRootPath = rootDirectoryPath;

        // Start processing in background - don't block UI
        unawaited(_processNewBooksInBackground(rootDirectoryPath));

      } else {
        debugPrint("Folder selection cancelled or resulted in null/empty path.");
      }
    } catch (e, stackTrace) {
      debugPrint("Error during addAudiobooksRecursively process: $e\n$stackTrace");
      _errorMessage = "An error occurred while accessing the file system.";
      notifyListeners();
    }
  }

  /// Process new books in background without blocking UI
  Future<void> _processNewBooksInBackground(String rootDirectoryPath) async {
    try {
      // Use the new recursive scanning method
      debugPrint("Starting invisible book scan...");
      final List<String> discoveredFolders = 
          await _metadataService.scanForAudiobookFolders(rootDirectoryPath);

      if (discoveredFolders.isEmpty) {
        _errorMessage = 
            "No audiobook folders found in the selected directory.\n\n"
            "Make sure your audiobooks are in folders containing audio files:\n"
            "• MP3, M4A, M4B, WAV, OGG, AAC, FLAC\n\n"
            "The scanner looks for folders with audio files at any depth in your folder structure.";
        debugPrint("No audiobook folders discovered in: $rootDirectoryPath");
        notifyListeners();
        return;
      }

      debugPrint("Found ${discoveredFolders.length} potential audiobook folders");
      int successCount = 0;
      int skipCount = 0;
      final List<String> newlyAddedPaths = [];

      // Process each discovered audiobook folder
      for (final folderPath in discoveredFolders) {
        try {
          // Skip if this folder is already in the library
          if (_audiobooks.any((book) => book.id == folderPath)) {
            debugPrint("Skipping already added audiobook: $folderPath");
            skipCount++;
            continue;
          }

          // Get audiobook details for this folder
          final newBook = await _metadataService.getAudiobookDetails(folderPath);

          if (newBook.chapters.isEmpty) {
            debugPrint("No valid chapters found in: $folderPath");
            skipCount++;
          } else {
            // Mark the new book as "new" (never played)
            _newBooks[newBook.id] = true;
            _lastPlayedTimestamps[newBook.id] = 0;
            _completedBooks[newBook.id] = false;

            _audiobooks.add(newBook);
            newlyAddedPaths.add(folderPath);
            successCount++;
            
            // Cache the new book metadata
            await _cacheBasicBookInfo(newBook, folderPath);
            await _cacheDetailedMetadata(newBook);
            
            // Update UI with each new book (seamless addition)
            _sortAudiobooksByStatus();
            notifyListeners();
            
            debugPrint("✓ Added: ${newBook.title} (${newBook.chapters.length} chapters)");
          }
          
          // Small delay to keep system responsive
          await Future.delayed(const Duration(milliseconds: 100));
          
        } catch (e) {
          debugPrint("Error processing audiobook folder $folderPath: $e");
          skipCount++;
        }
      }

      // Save the updated list of folder paths
      await _storageService.saveAudiobookFolders(
        _audiobooks.map((b) => b.id).toList(),
      );

      // Store for potential auto-tag creation
      if (successCount > 0 && _lastScannedRootPath != null) {
        if (newlyAddedPaths.isNotEmpty) {
          debugPrint("${newlyAddedPaths.length} new audiobooks added and ready for auto-tagging");
          _lastAddedPaths = newlyAddedPaths;
        }
      }

      // Clear any error message on success
      if (successCount > 0) {
        _errorMessage = null;
        debugPrint("Scan completed successfully: $successCount audiobooks added, $skipCount skipped");
      }
      
      notifyListeners();

    } catch (e, stackTrace) {
      debugPrint("Error during recursive audiobook scan: $e\n$stackTrace");
      _errorMessage = 
          "Failed to scan the selected folder.\n\n"
          "This could be due to:\n"
          "• Insufficient permissions\n"
          "• Corrupted files\n"
          "• Very large folder structure\n\n"
          "Please try again or choose a smaller folder.";
      notifyListeners();
    }
  }

  /// Add single audiobook folder
  Future<void> addAudiobookFolder() async {
    if (!await _requestPermissions()) {
      return;
    }

    try {
      // Use FilePicker to select a single directory path
      String? selectedDirectoryPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Single Audiobook Folder',
        lockParentWindow: true,
      );

      if (selectedDirectoryPath != null && selectedDirectoryPath.isNotEmpty) {
        debugPrint("Single audiobook folder selected: $selectedDirectoryPath");

        // Check if this exact path is already in the library
        if (_audiobooks.any((book) => book.id == selectedDirectoryPath)) {
          _errorMessage = "This audiobook folder is already in your library.";
          debugPrint("Attempted to add duplicate folder: $selectedDirectoryPath");
          notifyListeners();
          return;
        }

        // Process in background
        unawaited(_processSingleBookInBackground(selectedDirectoryPath));

      } else {
        debugPrint("Single folder selection cancelled.");
      }
    } catch (e, stackTrace) {
      debugPrint("Error during addAudiobookFolder process: $e\n$stackTrace");
      _errorMessage = "An error occurred while accessing the file system.";
      notifyListeners();
    }
  }

  /// Process single book in background
  Future<void> _processSingleBookInBackground(String selectedDirectoryPath) async {
    try {
      // Get audiobook details for the selected path
      final newBook = await _metadataService.getAudiobookDetails(selectedDirectoryPath);

      if (newBook.chapters.isEmpty) {
        _errorMessage =
            "The selected folder contains no compatible audio files.\n\n"
            "Supported formats: MP3, M4A, M4B, WAV, OGG, AAC, FLAC\n\n"
            "Please select a folder that contains audio files, or use "
            "'Add Multiple Books' to scan for audiobooks in subfolders.";
        debugPrint("No compatible chapters found in: $selectedDirectoryPath");
        notifyListeners();
      } else {
        // Mark the new book as "new" (never played)
        _newBooks[newBook.id] = true;
        _lastPlayedTimestamps[newBook.id] = 0;
        _completedBooks[newBook.id] = false;

        _audiobooks.add(newBook);
        _sortAudiobooksByStatus();

        // Cache the new book
        await _cacheBasicBookInfo(newBook, selectedDirectoryPath);
        await _cacheDetailedMetadata(newBook);

        // Save the updated list of folder paths
        await _storageService.saveAudiobookFolders(
          _audiobooks.map((b) => b.id).toList(),
        );

        // Store info for potential auto-tag creation from UI
        _lastScannedRootPath = Directory(selectedDirectoryPath).parent.path;
        _lastAddedPaths = [selectedDirectoryPath];
        debugPrint("Single audiobook added and ready for auto-tagging");
        
        _errorMessage = null;
        notifyListeners();
        debugPrint("Successfully added audiobook: ${newBook.title} with ${newBook.chapters.length} chapters");
      }
    } catch (e, stackTrace) {
      debugPrint("Error processing single audiobook folder: $e\n$stackTrace");
      _errorMessage = 
          "Failed to process the selected folder. The folder may be corrupted "
          "or contain unsupported file formats.";
      notifyListeners();
    }
  }

  /// Legacy method - now redirects to the new recursive method
  Future<void> addMultipleAudiobooks() async {
    await addAudiobooksRecursively();
  }

  /// Remove an audiobook from the library
  Future<bool> removeAudiobook(String audiobookId) async {
    try {
      // Find the index of the audiobook to remove
      final int index = _audiobooks.indexWhere((book) => book.id == audiobookId);

      if (index == -1) {
        debugPrint("Audiobook not found for removal: $audiobookId");
        return false;
      }

      // Remove the audiobook from our list
      _audiobooks.removeAt(index);

      // Remove any custom title for this audiobook
      _customTitles.remove(audiobookId);
      await _saveCustomTitles();

      // Remove from timestamps and states
      _lastPlayedTimestamps.remove(audiobookId);
      _newBooks.remove(audiobookId);
      _completedBooks.remove(audiobookId);

      // Save the updated list of folder paths
      await _storageService.saveAudiobookFolders(
        _audiobooks.map((b) => b.id).toList(),
      );

      // Also clear any saved position for this audiobook
      await _storageService.clearLastPosition(audiobookId);

      debugPrint("Successfully removed audiobook: $audiobookId");
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("Error removing audiobook: $e");
      return false;
    }
  }

  /// Opens the app's settings screen using permission_handler.
  Future<void> openSettings() async {
    debugPrint("Opening app settings...");
    await openAppSettings();
  }
}
