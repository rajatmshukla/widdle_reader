import 'dart:io'; // For Platform
import 'package:flutter/foundation.dart'; // For debugPrint and ChangeNotifier
import 'package:permission_handler/permission_handler.dart'; // For permissions
import 'package:file_picker/file_picker.dart'; // For picking folders
import 'package:device_info_plus/device_info_plus.dart'; // For Android version check

// Import local models and services
import '../models/audiobook.dart';
import '../services/metadata_service.dart';
import '../services/storage_service.dart';

class AudiobookProvider extends ChangeNotifier {
  final MetadataService _metadataService = MetadataService();
  final StorageService _storageService = StorageService();

  List<Audiobook> _audiobooks = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _permissionPermanentlyDenied = false;

  // New property for custom titles
  final Map<String, String> _customTitles = {};

  // Getters for state
  List<Audiobook> get audiobooks => _audiobooks;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get permissionPermanentlyDenied => _permissionPermanentlyDenied;

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

  /// Loads audiobook details from saved folder paths using StorageService.
  Future<void> loadAudiobooks() async {
    _isLoading = true;
    _errorMessage = null;
    _permissionPermanentlyDenied = false;
    notifyListeners(); // Notify UI about loading start

    // Ensure permissions are granted before accessing storage.
    if (!await _requestPermissions()) {
      _isLoading = false;
      // Error state handled within _requestPermissions
      notifyListeners();
      return;
    }

    try {
      // Load the list of saved folder paths (List<String>).
      final List<String> folderPaths =
          await _storageService.loadAudiobookFolders();
      final List<Audiobook> loadedBooks = [];

      // Process each saved path.
      for (final String path in folderPaths) {
        // Path here is guaranteed non-null by loadAudiobookFolders
        try {
          // Get details for the audiobook in this folder.
          // Audiobook ID (path) is non-nullable here.
          final book = await _metadataService.getAudiobookDetails(path);
          // Only add books that contain valid chapters.
          if (book.chapters.isNotEmpty) {
            loadedBooks.add(book);
          } else {
            debugPrint(
              "Skipping empty/invalid audiobook folder during load: $path",
            );
          }
        } catch (e, stackTrace) {
          debugPrint(
            "Error loading details for saved folder $path: $e\n$stackTrace",
          );
          // Optionally add placeholder/error state for this specific book
        }
      }
      // Sort the loaded books alphabetically.
      loadedBooks.sort(
        (a, b) => getTitleForAudiobook(
          a,
        ).toLowerCase().compareTo(getTitleForAudiobook(b).toLowerCase()),
      );
      _audiobooks = loadedBooks; // Update the internal list.
      debugPrint(
        "Finished loading ${loadedBooks.length} audiobooks from storage.",
      );
    } catch (e, stackTrace) {
      debugPrint("Error loading audiobook list from storage: $e\n$stackTrace");
      _errorMessage = "Failed to load library."; // Set general error message.
    } finally {
      _isLoading = false; // Ensure loading indicator stops.
      notifyListeners(); // Notify UI about loading completion/error.
    }
  }

  /// Requests necessary storage/media permissions based on Android version.
  Future<bool> _requestPermissions() async {
    PermissionStatus status;
    _permissionPermanentlyDenied = false; // Reset flag

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        // Android 13+
        status = await Permission.audio.request();
        await Permission.notification
            .request(); // Request notification permission too
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
      _errorMessage =
          "Permission denied. Please enable Storage/Media access in app settings.";
      _permissionPermanentlyDenied = true;
      debugPrint("Storage/Media permissions permanently denied.");
      notifyListeners();
      return false;
    } else {
      _errorMessage =
          "Storage/Media permission is required to access audiobooks.";
      debugPrint("Storage/Media permissions denied.");
      notifyListeners();
      return false;
    }
  }

  /// Allows the user to pick a folder using file_picker and adds it to the library.
  Future<void> addAudiobookFolder() async {
    _errorMessage = null;
    _permissionPermanentlyDenied = false;
    notifyListeners(); // Clear previous error messages from UI

    // Ensure permissions are granted before opening picker.
    if (!await _requestPermissions()) {
      // UI should show the error set by _requestPermissions
      return;
    }

    try {
      // Let the user pick a directory. Result is String? (nullable)
      String? selectedDirectoryPath = await FilePicker.platform
          .getDirectoryPath(
            dialogTitle: 'Select Audiobook Folder',
            lockParentWindow: true,
          );

      // *** FIX: Check if the path is non-null before proceeding ***
      if (selectedDirectoryPath != null && selectedDirectoryPath.isNotEmpty) {
        debugPrint("Folder selected: $selectedDirectoryPath");

        // Check if this exact path is already in the library.
        // Audiobook ID is the path (String).
        if (_audiobooks.any((book) => book.id == selectedDirectoryPath)) {
          _errorMessage = "Folder already exists in the library.";
          debugPrint(
            "Attempted to add duplicate folder: $selectedDirectoryPath",
          );
          notifyListeners();
          return;
        }

        _isLoading = true; // Show loading indicator while scanning the folder.
        notifyListeners();

        try {
          // Get audiobook details for the selected path (guaranteed non-null here).
          final newBook = await _metadataService.getAudiobookDetails(
            selectedDirectoryPath,
          );

          if (newBook.chapters.isEmpty) {
            _errorMessage =
                "Selected folder contains no compatible audio files or couldn't be read.";
            debugPrint(
              "No compatible chapters found in: $selectedDirectoryPath",
            );
          } else {
            _audiobooks.add(newBook); // Add the new book to the list.
            // Sort the library alphabetically after adding.
            _audiobooks.sort(
              (a, b) => getTitleForAudiobook(
                a,
              ).toLowerCase().compareTo(getTitleForAudiobook(b).toLowerCase()),
            );
            // Save the updated list of folder paths (all non-nullable Strings).
            // The map creates a new list of non-nullable strings.
            await _storageService.saveAudiobookFolders(
              _audiobooks.map((b) => b.id).toList(),
            );
            _errorMessage = null; // Clear error on success.
            debugPrint("Successfully added folder: $selectedDirectoryPath");
          }
        } catch (e, stackTrace) {
          debugPrint(
            "Error processing newly added folder $selectedDirectoryPath: $e\n$stackTrace",
          );
          _errorMessage = "Failed to process the selected folder.";
        } finally {
          _isLoading = false; // Hide loading indicator.
          notifyListeners(); // Update UI with new book or error.
        }
      } else {
        // User canceled the picker dialog or selected path was invalid/null.
        debugPrint(
          "Folder selection cancelled or resulted in null/empty path.",
        );
      }
    } catch (e, stackTrace) {
      // Catch potential errors from FilePicker itself or other unexpected issues.
      debugPrint("Error during addAudiobookFolder process: $e\n$stackTrace");
      _errorMessage = "An unexpected error occurred while adding the folder.";
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Remove an audiobook from the library
  Future<bool> removeAudiobook(String audiobookId) async {
    try {
      // Find the index of the audiobook to remove
      final int index = _audiobooks.indexWhere(
        (book) => book.id == audiobookId,
      );

      if (index == -1) {
        debugPrint("Audiobook not found for removal: $audiobookId");
        return false;
      }

      // Remove the audiobook from our list
      _audiobooks.removeAt(index);

      // Remove any custom title for this audiobook
      _customTitles.remove(audiobookId);
      await _saveCustomTitles();

      // Save the updated list of folder paths
      await _storageService.saveAudiobookFolders(
        _audiobooks.map((b) => b.id).toList(),
      );

      // Also clear any saved progress for this audiobook
      await _storageService.resetAudiobookProgress(audiobookId);

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
