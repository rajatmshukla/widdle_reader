import 'dart:io';
import 'dart:async'; // For unawaited
import 'dart:typed_data'; // For Uint8List
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:path/path.dart' as p;
import 'package:just_audio/just_audio.dart';
// Ensure flutter_media_metadata is correctly imported if used
import 'package:flutter_media_metadata/flutter_media_metadata.dart';

import '../models/audiobook.dart';
import '../models/chapter.dart';
import 'ffmpeg_helper.dart';

// CRITICAL FIX: Add release-safe logging for metadata service
void _logDebug(String message) {
  if (kDebugMode) {
    debugPrint(message);
  } else {
    print("[MetadataService] $message");
  }
}

class MetadataService {
  final List<String> _supportedFormats = const [
    // Make const
    '.mp3', '.m4a', '.m4b', '.wav', '.ogg', '.aac', '.flac', // Added flac
  ];

  final List<String> _coverArtFormats = const [
    '.jpg', '.jpeg', '.png', '.webp'
  ];

  /// Recursively scans a root directory for audiobook folders.
  /// Returns a list of discovered audiobook folder paths.
  Future<List<String>> scanForAudiobookFolders(String rootPath) async {
    _logDebug("Starting recursive scan for audiobooks in: $rootPath");
    
    final List<String> audiobookFolders = [];
    final rootDirectory = Directory(rootPath);
    
    if (!await rootDirectory.exists()) {
      debugPrint("Root directory does not exist: $rootPath");
      return audiobookFolders;
    }

    try {
      await _scanDirectoryRecursively(rootDirectory, audiobookFolders);
      _logDebug("Scan completed. Found ${audiobookFolders.length} audiobook folders");
      
      // Sort the folders for consistent ordering
      audiobookFolders.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      
      return audiobookFolders;
    } catch (e) {
      debugPrint("Error during recursive scan: $e");
      return audiobookFolders;
    }
  }



  /// Recursively scans a directory and its subdirectories for audiobook folders.
  /// A folder is considered an audiobook folder if it contains audio files.
  Future<void> _scanDirectoryRecursively(
    Directory directory, 
    List<String> audiobookFolders
  ) async {
    try {
      final List<FileSystemEntity> entities = await directory.list().toList();
      
      // Check if current directory contains audio files
      bool hasAudioFiles = false;
      bool hasSubdirectories = false;
      final List<Directory> subdirectories = [];
      
      debugPrint("Scanning directory: ${directory.path} (${entities.length} items)");
      
      for (final entity in entities) {
        if (entity is File) {
          final extension = p.extension(entity.path).toLowerCase();
          if (_supportedFormats.contains(extension)) {
            hasAudioFiles = true;
            debugPrint("  Found audio file: ${p.basename(entity.path)}");
            break; // Found audio files, no need to check further
          }
        } else if (entity is Directory) {
          hasSubdirectories = true;
          subdirectories.add(entity);
          debugPrint("  Found subdirectory: ${p.basename(entity.path)}");
        }
      }

      // If this directory has audio files, it's an audiobook folder
      if (hasAudioFiles) {
        debugPrint("✓ AUDIOBOOK FOLDER FOUND: ${directory.path}");
        audiobookFolders.add(directory.path);
        
        // Don't scan subdirectories if this folder has audio files
        // This prevents treating individual chapters as separate audiobooks
        return;
      }

      // If no audio files but has subdirectories, scan them recursively
      if (hasSubdirectories) {
        debugPrint("  No audio files found, scanning ${subdirectories.length} subdirectories...");
        for (final subdirectory in subdirectories) {
          await _scanDirectoryRecursively(subdirectory, audiobookFolders);
        }
      } else {
        // Empty directory or no relevant content
        debugPrint("  Skipping empty directory: ${directory.path}");
      }
    } catch (e) {
      debugPrint("Error scanning directory ${directory.path}: $e");
    }
  }

  /// Enhanced method to get audiobook details with better error handling and cover art detection
  Future<Audiobook> getAudiobookDetails(String folderPath) async {
    final directory = Directory(folderPath);
    List<Chapter> chapters = [];
    Duration totalDuration = Duration.zero;
    Uint8List? coverArt;
    String? author;

    if (!await directory.exists()) {
      debugPrint("Directory not found: $folderPath");
      // Return an empty audiobook object if the directory doesn't exist
      return Audiobook(
        id: folderPath,
        title: p.basename(folderPath),
        author: null,
        chapters: [],
        totalDuration: Duration.zero,
      );
    }

    try {
      final List<FileSystemEntity> files = await directory.list().toList();
      // Sort files alphabetically by base name for consistent chapter order
      files.sort(
        (a, b) => p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase()),
      );

      // Use a single player instance for duration checks
      final audioPlayer = AudioPlayer();

      // First pass: Collect audio files and any image files
      final List<File> audioFiles = [];
      final List<File> imageFiles = [];

      for (var entity in files) {
        if (entity is File) {
          final filePath = entity.path;
          final fileName = p.basename(filePath);
          final extension = p.extension(fileName).toLowerCase();

          // Check for audio files
          if (_supportedFormats.contains(extension)) {
            audioFiles.add(entity);
          }
          // Collect any image files for potential cover art
          else if (_coverArtFormats.contains(extension)) {
            imageFiles.add(entity);
          }
        }
      }

      // Second pass: Process audio files
      for (var audioFile in audioFiles) {
        final filePath = audioFile.path;
        final fileName = p.basename(filePath);
        
            try {
              final chapterId = filePath; // Use full path as unique ID
          String chapterTitle = p.basenameWithoutExtension(fileName); // Default title
              Duration? chapterDuration; // Make it explicitly nullable

              // --- FFmpeg Chapter Extraction ---
              // Check if the file has embedded chapters using FFmpeg
              List<Chapter> embeddedChapters = [];
              try {
                embeddedChapters = await FFmpegHelper.extractChapters(
                  filePath: filePath,
                  audiobookId: folderPath,
                );
              } catch (e) {
                debugPrint("FFmpeg extraction failed for $fileName: $e");
              }

              bool hasEmbeddedChapters = false;
              if (embeddedChapters.isNotEmpty) {
                debugPrint("Using ${embeddedChapters.length} embedded chapters from $fileName");
                chapters.addAll(embeddedChapters);
                hasEmbeddedChapters = true;
                // We proceed to metadata extraction to get cover art and author
              }

              // --- Metadata Extraction (Fallback/Standard) ---
              try {
                debugPrint("Attempting metadata extraction for: $fileName");
            final metadata = await MetadataRetriever.fromFile(audioFile);
            
                // Use metadata title if available, otherwise keep filename
            chapterTitle = metadata.trackName?.isNotEmpty == true
                        ? metadata.trackName!
                        : chapterTitle;
                
            // Extract author from first audio file if not set yet
            if (author == null && metadata.albumArtistName?.isNotEmpty == true) {
              author = metadata.albumArtistName;
            } else if (author == null && metadata.trackArtistNames?.isNotEmpty == true) {
              // Use the first artist name from the list
              author = metadata.trackArtistNames!.first;
            }
            
                // Metadata duration might be null or 0
            chapterDuration = (metadata.trackDuration != null &&
                            metadata.trackDuration! > 0)
                        ? Duration(milliseconds: metadata.trackDuration!)
                        : null; // Keep it null if metadata duration is invalid

            // Priority 1: Try to get cover art from embedded metadata
                if (coverArt == null &&
                    metadata.albumArt != null &&
                    metadata.albumArt!.isNotEmpty) {
                  coverArt = metadata.albumArt;
                  debugPrint("Found embedded cover art in: $fileName");
                }
                debugPrint(
              "Metadata for $fileName: Title='$chapterTitle', Duration=$chapterDuration, Author='$author'",
                );
              } catch (e) {
                debugPrint(
                  "MetadataRetriever failed for $fileName: $e. Will try just_audio for duration.",
                );
                // chapterDuration remains null here
              }

              // --- Fallback/Primary Duration Check with just_audio ---
              // If metadata didn't provide a valid duration, use just_audio
              // But skip if we already have chapters and a valid end time from them
              if ((chapterDuration == null || chapterDuration == Duration.zero) && 
                  (!hasEmbeddedChapters || embeddedChapters.last.end == null)) {
                try {
                  debugPrint("Using just_audio to get duration for: $fileName");
                  // setFilePath returns the duration
                  final durationOrNull = await audioPlayer.setFilePath(filePath);
                  if (durationOrNull != null && durationOrNull > Duration.zero) {
                    chapterDuration = durationOrNull;
                    debugPrint(
                      "just_audio duration for $fileName: $chapterDuration",
                    );
                  } else {
                    debugPrint(
                      "just_audio returned zero/null duration for $fileName. Skipping chapter.",
                    );
                    // chapterDuration remains null or zero, chapter will be skipped below
                  }
                } catch (audioError) {
                  debugPrint(
                    "Could not get duration for $fileName using just_audio: $audioError",
                  );
                  // chapterDuration remains null, chapter will be skipped below
                }
              }

              // If we still don't have duration but have embedded chapters, use the last chapter's end
              if ((chapterDuration == null || chapterDuration == Duration.zero) && 
                  hasEmbeddedChapters && embeddedChapters.last.end != null) {
                chapterDuration = embeddedChapters.last.end;
              }

              // --- Add Chapter ---
              // *** FIX: Only add chapter if duration is valid (not null and > 0) ***
              if (chapterDuration != null && chapterDuration > Duration.zero) {
                totalDuration += chapterDuration; // Add to total duration
                
                // Only add the file as a chapter if we didn't find embedded chapters
                if (!hasEmbeddedChapters) {
                  chapters.add(
                    Chapter(
                      id: chapterId,
                      title: chapterTitle,
                      audiobookId: folderPath,
                      sourcePath: filePath, // Add sourcePath
                      duration: chapterDuration, // Pass the non-nullable duration
                      start: Duration.zero,
                      end: chapterDuration,
                    ),
                  );
                }
              } else {
                debugPrint(
                  "Skipping chapter '$chapterTitle' due to zero or null duration.",
                );
              }
            } catch (e) {
              debugPrint("Error processing audio file $filePath: $e");
            }
          }

      // Priority 2: If no embedded cover art found, use any image file in the folder
      if (coverArt == null && imageFiles.isNotEmpty) {
        // Sort image files alphabetically for consistent selection
        imageFiles.sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
        
        for (var imageFile in imageFiles) {
          try {
            final fileName = p.basename(imageFile.path);
            debugPrint("Attempting to use image file as cover: $fileName");
            coverArt = await imageFile.readAsBytes();
            if (coverArt != null && coverArt.isNotEmpty) {
              debugPrint("Successfully loaded cover art from: $fileName");
              break; // Use the first valid image file
            } else {
              coverArt = null; // Reset if file is empty
              debugPrint("Image file $fileName is empty, trying next...");
            }
          } catch (e) {
            debugPrint("Error reading image file ${p.basename(imageFile.path)}: $e");
          }
        }
      }
      
      // Dispose the temporary player when done
      await audioPlayer.dispose();
      debugPrint("Finished processing folder: $folderPath");
    } catch (e) {
      debugPrint("Error listing or processing files in $folderPath: $e");
      // Return empty audiobook on listing error
      return Audiobook(
        id: folderPath,
        title: p.basename(folderPath),
        author: null,
        chapters: [],
        totalDuration: Duration.zero,
      );
    }

    // Return the fully processed Audiobook object
    return Audiobook(
      id: folderPath, // Folder path as unique ID
      title: p.basename(folderPath), // Use folder name as title
      author: author, // Author extracted from metadata
      chapters: chapters,
      totalDuration: totalDuration,
      coverArt: coverArt,
    );
  }

  /// Extracts potential tag names from folder structure
  /// Analyzes the path relative to the root to identify series, authors, and genres
  List<String> extractPotentialTags(String audiobookPath, String rootPath) {
    final List<String> potentialTags = [];
    
    try {
      debugPrint("Extracting potential tags:");
      debugPrint("  audiobookPath: $audiobookPath");
      debugPrint("  rootPath: $rootPath");
      
      // Get the relative path from root to audiobook
      String relativePath = p.relative(audiobookPath, from: rootPath);
      debugPrint("  relativePath: $relativePath");
      
      // Split the path into segments
      final pathSegments = p.split(relativePath);
      debugPrint("  pathSegments: $pathSegments");
      
      // Remove the last segment (audiobook folder itself)
      if (pathSegments.isNotEmpty) {
        pathSegments.removeLast();
        debugPrint("  pathSegments after removing last: $pathSegments");
      }
      
      // Each remaining segment is a potential tag
      for (final segment in pathSegments) {
        final cleanedSegment = _cleanTagName(segment);
        debugPrint("  cleaning '$segment' -> '$cleanedSegment'");
        if (cleanedSegment.isNotEmpty && cleanedSegment.length > 2) {
          potentialTags.add(cleanedSegment);
          debugPrint("  added tag: '$cleanedSegment'");
        } else {
          debugPrint("  skipped tag (too short or empty): '$cleanedSegment'");
        }
      }
      
      debugPrint("Final extracted potential tags for $audiobookPath: $potentialTags");
      
    } catch (e) {
      debugPrint("Error extracting potential tags from $audiobookPath: $e");
    }
    
    return potentialTags;
  }

  /// Cleans and normalizes tag names
  String _cleanTagName(String tagName) {
    // Remove common prefixes and suffixes
    String cleaned = tagName.trim();
    
    // Remove common patterns
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' '); // Multiple spaces to single
    cleaned = cleaned.replaceAll(RegExp(r'[_\-]+'), ' '); // Underscores and dashes to spaces
    
    // Remove leading/trailing special characters
    cleaned = cleaned.replaceAll(RegExp(r'^[^\w\s]+|[^\w\s]+$'), '');
    
    // Title case for better presentation
    cleaned = _toTitleCase(cleaned);
    
    return cleaned.trim();
  }

  /// Converts string to title case
  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    
    return text.toLowerCase().split(' ').map((word) {
      if (word.isEmpty) return word;
      
      // Handle special cases for common words
      final lowerWord = word.toLowerCase();
      if (['the', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with', 'by'].contains(lowerWord)) {
        return lowerWord;
      }
      
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  /// Suggests tag names based on folder structure analysis with smart series consolidation
  /// This method analyzes common patterns to suggest better tag names
  List<String> suggestTagNames(List<String> audiobookPaths, String rootPath) {
    final Map<String, int> tagCounts = {};
    final Map<String, Set<String>> tagToBooks = {};
    
    // Collect all potential tags and count their usage
    for (final audiobookPath in audiobookPaths) {
      final tags = extractPotentialTags(audiobookPath, rootPath);
      for (final tag in tags) {
        tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
        tagToBooks.putIfAbsent(tag, () => <String>{});
        tagToBooks[tag]!.add(p.basename(audiobookPath));
      }
    }
    
    // Consolidate similar series tags before suggesting
    final consolidatedTags = _consolidateSimilarTags(tagCounts, tagToBooks);
    
    // Filter tags that apply to multiple books (likely series or genres)
    final suggestedTags = <String>[];
    for (final entry in consolidatedTags.entries) {
      final tagName = entry.key;
      final count = entry.value['count'] as int;
      final books = entry.value['books'] as Set<String>;
      
      // Only suggest tags that apply to multiple books
      if (count > 1) {
        suggestedTags.add(tagName);
        debugPrint("Suggested consolidated tag '$tagName' for $count books: ${books.take(3).join(', ')}${count > 3 ? '...' : ''}");
      }
    }
    
    // Sort by frequency (most common first)
    suggestedTags.sort((a, b) {
      final aCount = consolidatedTags[a]?['count'] as int? ?? 0;
      final bCount = consolidatedTags[b]?['count'] as int? ?? 0;
      return bCount.compareTo(aCount);
    });
    
    return suggestedTags;
  }

  /// Consolidates similar tags (especially series) into single representative tags
  Map<String, Map<String, dynamic>> _consolidateSimilarTags(
    Map<String, int> tagCounts,
    Map<String, Set<String>> tagToBooks,
  ) {
    final consolidated = <String, Map<String, dynamic>>{};
    final processed = <String>{};
    
    for (final entry in tagCounts.entries) {
      final tagName = entry.key;
      final count = entry.value;
      
      if (processed.contains(tagName)) continue;
      
      // Find all similar tags that should be consolidated
      final similarTags = <String>[tagName];
      final allBooks = Set<String>.from(tagToBooks[tagName] ?? {});
      int totalCount = count;
      
      for (final otherTag in tagCounts.keys) {
        if (otherTag != tagName && !processed.contains(otherTag)) {
          if (_areTagsSimilarForConsolidation(tagName, otherTag)) {
            similarTags.add(otherTag);
            allBooks.addAll(tagToBooks[otherTag] ?? {});
            totalCount += tagCounts[otherTag] ?? 0;
            processed.add(otherTag);
          }
        }
      }
      
      // Choose the best representative name from similar tags
      final bestName = _chooseBestTagName(similarTags);
      
      consolidated[bestName] = {
        'count': allBooks.length, // Use unique book count, not sum of counts
        'books': allBooks,
        'originalTags': similarTags,
      };
      
      processed.add(tagName);
      
      if (similarTags.length > 1) {
        debugPrint("Consolidated ${similarTags.length} similar tags into '$bestName': ${similarTags.join(', ')}");
      }
    }
    
    return consolidated;
  }

  /// Determines if two tags should be consolidated (stricter than similarity checking)
  bool _areTagsSimilarForConsolidation(String tag1, String tag2) {
    final clean1 = _cleanTagNameForConsolidation(tag1);
    final clean2 = _cleanTagNameForConsolidation(tag2);
    
    // Must have the same core name to be consolidated
    if (clean1 == clean2 && clean1.isNotEmpty) {
      return true;
    }
    
    // Check for very high similarity (95% for consolidation vs 85% for duplicate detection)
    if (clean1.length > 2 && clean2.length > 2) {
      final similarity = _calculateStringSimilarity(clean1, clean2);
      return similarity > 0.95;
    }
    
    return false;
  }

  /// Cleans tag names specifically for consolidation (more aggressive than normalization)
  String _cleanTagNameForConsolidation(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'\b(?:series|book|vol|volume|part|chapter|the)\s*\d*\b'), '')
        .replaceAll(RegExp(r'\b\d+\b'), '') // Remove standalone numbers
        .replaceAll(RegExp(r'[^\w\s]'), '') // Remove special characters
        .replaceAll(RegExp(r'\s+'), ' ')    // Normalize whitespace
        .trim();
  }

  /// Chooses the best representative name from similar tags
  String _chooseBestTagName(List<String> similarTags) {
    if (similarTags.length == 1) return similarTags.first;
    
    // Prefer shorter, cleaner names
    similarTags.sort((a, b) {
      // First, prefer tags without numbers
      final aHasNumbers = RegExp(r'\d').hasMatch(a);
      final bHasNumbers = RegExp(r'\d').hasMatch(b);
      
      if (aHasNumbers != bHasNumbers) {
        return aHasNumbers ? 1 : -1; // Prefer tag without numbers
      }
      
      // Then prefer shorter names
      final lengthComparison = a.length.compareTo(b.length);
      if (lengthComparison != 0) return lengthComparison;
      
      // Finally, alphabetical order
      return a.compareTo(b);
    });
    
    return similarTags.first;
  }

  /// Calculates string similarity using Jaccard coefficient
  double _calculateStringSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;
    
    final set1 = s1.split('').toSet();
    final set2 = s2.split('').toSet();
    
    final intersection = set1.intersection(set2).length;
    final union = set1.union(set2).length;
    
    return union > 0 ? intersection / union : 0.0;
  }

  /// ========================================
  /// PERFORMANCE OPTIMIZATION - LAZY LOADING
  /// ========================================

  /// Gets basic audiobook info for fast initial loading
  /// Returns lightweight data: title, author, folder path, chapter count
  Future<Audiobook> getBasicAudiobookInfo(String folderPath) async {
    final directory = Directory(folderPath);
    
    if (!await directory.exists()) {
      debugPrint("Directory not found: $folderPath");
      return Audiobook(
        id: folderPath,
        title: p.basename(folderPath),
        author: null,
        chapters: [],
        totalDuration: Duration.zero,
      );
    }

    try {
      // Quick scan for audio files without full processing
      final List<FileSystemEntity> files = await directory.list().toList();
      final List<File> audioFiles = [];
      String? author;
      
      for (var entity in files) {
        if (entity is File) {
          final extension = p.extension(entity.path).toLowerCase();
          if (_supportedFormats.contains(extension)) {
            audioFiles.add(entity);
          }
        }
      }

      // Try to get author from first audio file metadata (quick check)
      if (audioFiles.isNotEmpty) {
        try {
          final metadata = await MetadataRetriever.fromFile(audioFiles.first);
          author = metadata.albumArtistName?.isNotEmpty == true
              ? metadata.albumArtistName
              : metadata.trackArtistNames?.isNotEmpty == true
                  ? metadata.trackArtistNames!.first
                  : null;
        } catch (e) {
          // Ignore metadata errors for basic info
          debugPrint("Could not extract basic metadata from ${audioFiles.first.path}: $e");
        }
      }

      // Create basic chapters (no duration calculation yet)
      final List<Chapter> basicChapters = audioFiles.map((file) {
        final fileName = p.basename(file.path);
        return Chapter(
          id: file.path,
          title: p.basenameWithoutExtension(fileName),
          audiobookId: folderPath,
          sourcePath: file.path, // Add sourcePath
          duration: Duration.zero, // Will be loaded later
        );
      }).toList();

      // Sort chapters by filename
      basicChapters.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

      return Audiobook(
        id: folderPath,
        title: p.basename(folderPath),
        author: author,
        chapters: basicChapters,
        totalDuration: Duration.zero, // Will be calculated later
        // coverArt left null - will be loaded on-demand
      );

    } catch (e) {
      debugPrint("Error getting basic audiobook info for $folderPath: $e");
      return Audiobook(
        id: folderPath,
        title: p.basename(folderPath),
        author: null,
        chapters: [],
        totalDuration: Duration.zero,
      );
    }
  }

  /// Loads detailed metadata on-demand (durations, cover art)
  /// This method is called when the user scrolls to or interacts with a book
  Future<Audiobook> loadDetailedMetadata(Audiobook basicBook) async {
    final folderPath = basicBook.id;
    final directory = Directory(folderPath);
    
    if (!await directory.exists()) {
      debugPrint("Directory not found during detailed loading: $folderPath");
      return basicBook;
    }

    try {
      final List<FileSystemEntity> files = await directory.list().toList();
      final List<File> audioFiles = [];
      final List<File> imageFiles = [];
      
      // Collect audio and image files
      for (var entity in files) {
        if (entity is File) {
          final extension = p.extension(entity.path).toLowerCase();
          if (_supportedFormats.contains(extension)) {
            audioFiles.add(entity);
          } else if (_coverArtFormats.contains(extension)) {
            imageFiles.add(entity);
          }
        }
      }

      // Sort audio files to match basic chapters order
      audioFiles.sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));

      Duration totalDuration = Duration.zero;
      final List<Chapter> detailedChapters = [];
      Uint8List? coverArt;

      // Use a single player instance for duration checks
      final audioPlayer = AudioPlayer();

      try {
        // Process audio files for detailed metadata
        for (int i = 0; i < audioFiles.length; i++) {
          final audioFile = audioFiles[i];
          final filePath = audioFile.path;
          final fileName = p.basename(filePath);
          
          String chapterTitle = p.basenameWithoutExtension(fileName);
          Duration? chapterDuration;

          try {
            // Try metadata first for title and embedded cover art
            final metadata = await MetadataRetriever.fromFile(audioFile);
            
            chapterTitle = metadata.trackName?.isNotEmpty == true
                ? metadata.trackName!
                : chapterTitle;

            // Extract embedded cover art from first file if not found yet
            if (coverArt == null && metadata.albumArt != null && metadata.albumArt!.isNotEmpty) {
              coverArt = Uint8List.fromList(metadata.albumArt!);
              debugPrint("Found embedded cover art in: $fileName");
            }

            // Try to get duration from metadata first
            if (metadata.trackDuration != null && metadata.trackDuration! > 0) {
              chapterDuration = Duration(milliseconds: metadata.trackDuration!);
              debugPrint("Metadata duration for $fileName: $chapterDuration");
            }
          } catch (e) {
            debugPrint("Error extracting detailed metadata from $fileName: $e");
          }

          // If no duration from metadata, use just_audio
          if (chapterDuration == null || chapterDuration == Duration.zero) {
            try {
              final durationOrNull = await audioPlayer.setFilePath(filePath);
              if (durationOrNull != null && durationOrNull > Duration.zero) {
                chapterDuration = durationOrNull;
                debugPrint("just_audio duration for $fileName: $chapterDuration");
              }
            } catch (audioError) {
              debugPrint("Could not get duration for $fileName using just_audio: $audioError");
            }
          }

          // Only add chapter if duration is valid
          if (chapterDuration != null && chapterDuration > Duration.zero) {
            totalDuration += chapterDuration;
            detailedChapters.add(
              Chapter(
                id: filePath,
                title: chapterTitle,
                audiobookId: folderPath,
                sourcePath: filePath, // Add sourcePath
                duration: chapterDuration,
                start: Duration.zero,
                end: chapterDuration,
              ),
            );
          } else {
            debugPrint("Skipping chapter '$chapterTitle' due to zero or null duration.");
          }
        }

        // If no embedded cover art found, try image files
        if (coverArt == null && imageFiles.isNotEmpty) {
          imageFiles.sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
          
          for (var imageFile in imageFiles) {
            try {
              final fileName = p.basename(imageFile.path);
              debugPrint("Attempting to use image file as cover: $fileName");
              coverArt = await imageFile.readAsBytes();
              if (coverArt != null && coverArt.isNotEmpty) {
                debugPrint("Successfully loaded cover art from: $fileName");
                break;
              } else {
                coverArt = null;
              }
            } catch (e) {
              debugPrint("Error reading image file ${p.basename(imageFile.path)}: $e");
            }
          }
        }

      } finally {
        await audioPlayer.dispose();
      }

      // Return updated audiobook with detailed metadata
      return Audiobook(
        id: basicBook.id,
        title: basicBook.title,
        author: basicBook.author,
        chapters: detailedChapters,
        totalDuration: totalDuration,
        coverArt: coverArt,
      );

    } catch (e) {
      debugPrint("Error loading detailed metadata for $folderPath: $e");
      return basicBook; // Return original basic book if detailed loading fails
    }
  }

  /// Batch load basic info for multiple audiobooks (parallel processing)
  Future<List<Audiobook>> loadBasicInfoBatch(List<String> folderPaths, {int batchSize = 5}) async {
    final List<Audiobook> results = [];
    
    // Process in batches to avoid overwhelming the system
    for (int i = 0; i < folderPaths.length; i += batchSize) {
      final batch = folderPaths.sublist(i, (i + batchSize).clamp(0, folderPaths.length));
      
      debugPrint("Loading basic info batch ${(i ~/ batchSize) + 1} (${batch.length} books)...");
      
      // Process batch in parallel
      final futures = batch.map((path) => getBasicAudiobookInfo(path));
      final batchResults = await Future.wait(futures);
      
      // Filter out empty books
      final validBooks = batchResults.where((book) => book.chapters.isNotEmpty).toList();
      results.addAll(validBooks);
      
      debugPrint("Batch completed: ${validBooks.length}/${batch.length} books loaded");
    }
    
    return results;
  }

  /// Preload cover art for visible audiobooks in background
  Future<void> preloadCoverArt(List<String> audiobookIds) async {
    for (final audiobookId in audiobookIds) {
      try {
        // This would run in background, so we don't await it
        unawaited(_loadCoverArtInBackground(audiobookId));
      } catch (e) {
        debugPrint("Error starting background cover art load for $audiobookId: $e");
      }
    }
  }

  /// Background method to load cover art without blocking UI
  Future<void> _loadCoverArtInBackground(String audiobookId) async {
    try {
      final directory = Directory(audiobookId);
      if (!await directory.exists()) return;

      final files = await directory.list().toList();
      final imageFiles = files
          .whereType<File>()
          .where((file) => _coverArtFormats.contains(p.extension(file.path).toLowerCase()))
          .toList();

      if (imageFiles.isNotEmpty) {
        imageFiles.sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
        final coverArt = await imageFiles.first.readAsBytes();
        
        // Could cache this result here for future use
        debugPrint("Background loaded cover art for $audiobookId");
      }
    } catch (e) {
      debugPrint("Error in background cover art loading for $audiobookId: $e");
    }
  }
}
