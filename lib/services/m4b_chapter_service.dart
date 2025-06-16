import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:metadata_god/metadata_god.dart';
import 'package:id3tag/id3tag.dart';
import '../models/m4b_chapter.dart';

class M4BChapterService {
  /// Extracts embedded chapters from an M4B file
  /// Returns a list of M4BChapter objects if chapters are found
  /// Returns null if no chapters are found or if extraction fails
  Future<List<M4BChapter>?> extractM4BChapters(String filePath) async {
    if (!await _isM4BFile(filePath)) {
      debugPrint("File is not an M4B file: $filePath");
      return null;
    }

    debugPrint("Attempting to extract M4B chapters from: $filePath");

    // Try id3tag first (for files with ID3 chapter tags) - more reliable for chapters
    final id3Chapters = await _extractWithId3Tag(filePath);
    if (id3Chapters != null && id3Chapters.isNotEmpty) {
      debugPrint("Successfully extracted ${id3Chapters.length} chapters using id3tag");
      return id3Chapters;
    }

    debugPrint("No chapters found in M4B file: $filePath");
    return null;
  }

  /// Check if the file is an M4B audiobook file
  Future<bool> _isM4BFile(String filePath) async {
    final extension = p.extension(filePath).toLowerCase();
    return extension == '.m4b' || extension == '.m4a';
  }

  /// Extract chapters using id3tag package
  Future<List<M4BChapter>?> _extractWithId3Tag(String filePath) async {
    try {
      debugPrint("Trying id3tag for: $filePath");
      
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint("File does not exist: $filePath");
        return null;
      }

      // Use the correct API for id3tag package
      final parser = ID3TagReader.path(filePath);
      final tag = await parser.readTag();
      
      // Check if tag was found and has chapters
      final chapters = tag.chapters;
      if (chapters == null || chapters.isEmpty) {
        debugPrint("No chapters found in ID3 tag (found: ${chapters?.length ?? 0})");
        return null;
      }

      debugPrint("Found ${chapters.length} chapters in ID3 tag");

      // Convert ID3 chapters to M4BChapter objects
      final m4bChapters = <M4BChapter>[];
      
      for (int i = 0; i < chapters.length; i++) {
        final chapter = chapters[i];
        
        // Debug: Print available properties
        debugPrint("Chapter $i properties: ${chapter.toString()}");
        
        // Try different possible property names for start time
        Duration startTime = Duration.zero;
        Duration duration = const Duration(minutes: 5); // Default fallback
        
        try {
          // Try accessing different possible property names
          if (chapter.runtimeType.toString().contains('startTime')) {
            final startTimeValue = (chapter as dynamic).startTime ?? 0;
            final startTimeMs = (startTimeValue is double ? startTimeValue.toInt() : startTimeValue) as int;
            startTime = Duration(milliseconds: startTimeMs);
          } else if (chapter.runtimeType.toString().contains('startTimeMs')) {
            final startTimeValue = (chapter as dynamic).startTimeMs ?? 0;
            final startTimeMs = (startTimeValue is double ? startTimeValue.toInt() : startTimeValue) as int;
            startTime = Duration(milliseconds: startTimeMs);
          }
        } catch (e) {
          debugPrint("Error accessing chapter start time: $e");
        }

        final chapterTitle = chapter.title?.isNotEmpty == true 
            ? chapter.title! 
            : 'Chapter ${i + 1}';

        final m4bChapter = M4BChapter(
          id: '${filePath}_chapter_$i',
          title: chapterTitle,
          startTime: startTime,
          duration: duration,
          audiobookId: filePath,
        );

        m4bChapters.add(m4bChapter);
      }

      return m4bChapters;
      
    } catch (e) {
      debugPrint("Error extracting chapters with id3tag: $e");
      return null;
    }
  }

  /// Get the total duration of an M4B file
  Future<Duration?> getM4BDuration(String filePath) async {
    try {
      await MetadataGod.initialize();
      final metadata = await MetadataGod.readMetadata(file: filePath);
      
      if (metadata.durationMs != null && metadata.durationMs! > 0) {
        // Convert double to int for Duration constructor
        final durationValue = metadata.durationMs!;
        final durationMs = (durationValue is double ? durationValue.toInt() : durationValue) as int;
        return Duration(milliseconds: durationMs);
      }
      
      return null;
    } catch (e) {
      debugPrint("Error getting M4B duration: $e");
      return null;
    }
  }

  /// Check if a file has embedded chapters
  Future<bool> hasEmbeddedChapters(String filePath) async {
    final chapters = await extractM4BChapters(filePath);
    return chapters != null && chapters.isNotEmpty;
  }
} 