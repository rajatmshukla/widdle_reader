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

  Future<Audiobook> getAudiobookDetails(String folderPath) async {
    final directory = Directory(folderPath);
    List<Chapter> chapters = [];
    Duration totalDuration = Duration.zero;
    Uint8List? coverArt;

    if (!await directory.exists()) {
      debugPrint("Directory not found: $folderPath");
      // Return an empty audiobook object if the directory doesn't exist
      return Audiobook(
        id: folderPath,
        title: p.basename(folderPath),
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

      for (var entity in files) {
        if (entity is File) {
          final filePath = entity.path;
          final fileName = p.basename(filePath);
          final extension = p.extension(fileName).toLowerCase();

          // Check for audio files
          if (_supportedFormats.contains(extension)) {
            try {
              final chapterId = filePath; // Use full path as unique ID
              String chapterTitle = p.basenameWithoutExtension(
                fileName,
              ); // Default title
              Duration? chapterDuration; // Make it explicitly nullable

              // --- Metadata Extraction ---
              try {
                debugPrint("Attempting metadata extraction for: $fileName");
                final metadata = await MetadataRetriever.fromFile(
                  File(filePath),
                );
                // Use metadata title if available, otherwise keep filename
                chapterTitle =
                    metadata.trackName?.isNotEmpty == true
                        ? metadata.trackName!
                        : chapterTitle;
                // Metadata duration might be null or 0
                chapterDuration =
                    (metadata.trackDuration != null &&
                            metadata.trackDuration! > 0)
                        ? Duration(milliseconds: metadata.trackDuration!)
                        : null; // Keep it null if metadata duration is invalid

                // Attempt to get cover art from metadata (only once)
                if (coverArt == null &&
                    metadata.albumArt != null &&
                    metadata.albumArt!.isNotEmpty) {
                  coverArt = metadata.albumArt;
                  debugPrint("Found cover art via metadata in: $fileName");
                }
                debugPrint(
                  "Metadata for $fileName: Title='$chapterTitle', Duration=$chapterDuration",
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
                  final durationOrNull = await audioPlayer.setFilePath(
                    filePath,
                  );
                  if (durationOrNull != null &&
                      durationOrNull > Duration.zero) {
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
          // Check for common cover art filenames (only if cover not found yet)
          else if (coverArt == null &&
              (fileName.toLowerCase() == 'cover.jpg' ||
                  fileName.toLowerCase() == 'folder.jpg')) {
            try {
              debugPrint("Attempting to read cover file: $fileName");
              coverArt = await entity.readAsBytes();
              if (coverArt.isNotEmpty) {
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
      // Dispose the temporary player when done
      await audioPlayer.dispose();
      debugPrint("Finished processing folder: $folderPath");
    } catch (e) {
      debugPrint("Error listing or processing files in $folderPath: $e");
      // Return empty audiobook on listing error
      return Audiobook(
        id: folderPath,
        title: p.basename(folderPath),
        chapters: [],
        totalDuration: Duration.zero,
      );
    }

    // Return the fully processed Audiobook object
    return Audiobook(
      id: folderPath, // Folder path as unique ID
      title: p.basename(folderPath), // Use folder name as title
      chapters: chapters,
      totalDuration: totalDuration,
      coverArt: coverArt,
    );
  }
}
