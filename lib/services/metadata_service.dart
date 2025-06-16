import 'dart:io';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:path/path.dart' as p;
import 'package:just_audio/just_audio.dart';
// Ensure flutter_media_metadata is correctly imported if used
import 'package:flutter_media_metadata/flutter_media_metadata.dart';

import '../models/audiobook.dart';
import '../models/chapter.dart';

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
    debugPrint("Starting recursive scan for audiobooks in: $rootPath");
    
    final List<String> audiobookFolders = [];
    final rootDirectory = Directory(rootPath);
    
    if (!await rootDirectory.exists()) {
      debugPrint("Root directory does not exist: $rootPath");
      return audiobookFolders;
    }

    try {
      await _scanDirectoryRecursively(rootDirectory, audiobookFolders);
      debugPrint("Scan completed. Found ${audiobookFolders.length} audiobook folders");
      
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

      // First pass: Look for cover art and collect audio files
      final List<File> audioFiles = [];
      
      for (var entity in files) {
        if (entity is File) {
          final filePath = entity.path;
          final fileName = p.basename(filePath);
          final extension = p.extension(fileName).toLowerCase();

          // Check for audio files
          if (_supportedFormats.contains(extension)) {
            audioFiles.add(entity);
          }
          // Check for cover art files
          else if (coverArt == null && _coverArtFormats.contains(extension)) {
            // Check for common cover art filenames
            final baseName = p.basenameWithoutExtension(fileName).toLowerCase();
            if (baseName == 'cover' || 
                baseName == 'folder' || 
                baseName == 'albumart' || 
                baseName == 'front' ||
                baseName == 'artwork') {
              try {
                debugPrint("Attempting to read cover file: $fileName");
                coverArt = await entity.readAsBytes();
                if (coverArt != null && coverArt.isNotEmpty) {
                  debugPrint("Found cover art file: $fileName");
                } else {
                  coverArt = null; // Reset if file is empty
                  debugPrint("Cover file $fileName is empty.");
                }
              } catch (e) {
                debugPrint("Error reading cover file $fileName: $e");
              }
            }
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

          // --- Metadata Extraction ---
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

            // Attempt to get cover art from metadata (only if not found in files)
            if (coverArt == null &&
                metadata.albumArt != null &&
                metadata.albumArt!.isNotEmpty) {
              coverArt = metadata.albumArt;
              debugPrint("Found cover art via metadata in: $fileName");
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
          if (chapterDuration == null || chapterDuration == Duration.zero) {
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

          // --- Add Chapter ---
          // *** FIX: Only add chapter if duration is valid (not null and > 0) ***
          if (chapterDuration != null && chapterDuration > Duration.zero) {
            totalDuration += chapterDuration; // Add to total duration
            chapters.add(
              Chapter(
                id: chapterId,
                title: chapterTitle,
                audiobookId: folderPath,
                duration: chapterDuration, // Pass the non-nullable duration
              ),
            );
          } else {
            debugPrint(
              "Skipping chapter '$chapterTitle' due to zero or null duration.",
            );
          }
        } catch (e) {
          debugPrint("Error processing audio file $filePath: $e");
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
}
