import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:just_audio/just_audio.dart';
import 'cue_parser.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';

import '../models/audiobook.dart';
import '../models/chapter.dart';
import 'ffmpeg_helper.dart';
import 'cover_art_service.dart';
import 'storage_service.dart';
import 'native_scanner.dart';

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
    '.mp3', '.m4a', '.m4b', '.wav', '.ogg', '.aac', '.flac', '.opus',
    '.mp4', '.m4v', '.m4p', '.wma',
  ];

  final List<String> _coverArtFormats = const [
    '.jpg', '.jpeg', '.png', '.webp'
  ];

  /// Recursively scans a root directory for audiobook folders.
  /// Supports both standard filesystem paths and SAF content Uris.
  /// PERFORMANCE FIX: Offloads recursive scanning to native side.
  Future<List<String>> scanForAudiobookFolders(String rootPath) async {
    _logDebug("Starting native recursive scan for audiobooks in: $rootPath");
    
    try {
      if (Platform.isAndroid) {
        final List<String> audiobookFolders = await NativeScanner.recursiveScan(rootPath);
        _logDebug("Native recursive scan completed. Found ${audiobookFolders.length} audiobook folders.");
        
        // Sort the folders for consistent ordering
        audiobookFolders.sort((a, b) => _naturalCompare(a, b));
        return audiobookFolders;
      } else {
        // Fallback for non-Android platforms
        final List<String> audiobookFolders = [];
        final rootDirectory = Directory(rootPath);
        if (!await rootDirectory.exists()) {
          debugPrint("Root directory does not exist: $rootPath");
          return audiobookFolders;
        }
        await _scanDirectoryRecursivelyFallback(rootDirectory, audiobookFolders);
        audiobookFolders.sort((a, b) => _naturalCompare(a, b));
        return audiobookFolders;
      }
    } catch (e) {
      _logDebug("Error during recursive scan for $rootPath: $e");
      return [];
    }
  }

  /// Fallback recursive scan for non-Android platforms
  Future<void> _scanDirectoryRecursivelyFallback(
    Directory directory, 
    List<String> audiobookFolders
  ) async {
    try {
      bool hasAudioFilesInThisDir = false;
      final List<Directory> subdirectoriesToScan = [];
      
      await for (final entity in directory.list(followLinks: false)) {
        try {
          if (entity is File) {
            final fileName = p.basename(entity.path);
            final extension = p.extension(fileName).toLowerCase();
            
            if (fileName.toLowerCase() == '.nomedia' || 
                fileName == '.DS_Store' || 
                fileName.toLowerCase() == 'thumbs.db') {
              continue; 
            }
            
            if (_supportedFormats.contains(extension)) {
              hasAudioFilesInThisDir = true;
            }
          } else if (entity is Directory) {
            subdirectoriesToScan.add(entity);
          }
        } catch (e) {
          _logDebug("  Error processing entity ${entity.path}: $e. Skipping.");
        }
      }

      if (hasAudioFilesInThisDir) {
        audiobookFolders.add(directory.path);
      }

      for (final subdirectory in subdirectoriesToScan) {
        await _scanDirectoryRecursivelyFallback(subdirectory, audiobookFolders);
      }
    } catch (e) {
      _logDebug("✗ Error scanning directory ${directory.path}: $e. Skipping branch.");
    }
  }

  /// Natural sort comparator for alphanumeric strings (e.g. "Chapter 2" < "Chapter 10")
  static int _naturalCompare(String a, String b) {
    if (a == b) return 0;
    
    final aStr = a.toLowerCase();
    final bStr = b.toLowerCase();
    
    if (aStr == bStr) return a.compareTo(b); // Tie-breaker for case sensitivity
    
    final re = RegExp(r'(\d+)|(\D+)');
    final aMatches = re.allMatches(aStr).toList();
    final bMatches = re.allMatches(bStr).toList();
    
    for (int i = 0; i < aMatches.length && i < bMatches.length; i++) {
      final aRaw = aMatches[i].group(0)!;
      final bRaw = bMatches[i].group(0)!;
      
      final aIsDigit = RegExp(r'^\d+$').hasMatch(aRaw);
      final bIsDigit = RegExp(r'^\d+$').hasMatch(bRaw);
      
      if (aIsDigit && bIsDigit) {
        final aNum = BigInt.parse(aRaw);
        final bNum = BigInt.parse(bRaw);
        if (aNum != bNum) return aNum.compareTo(bNum);
        
        if (aRaw.length != bRaw.length) return aRaw.length.compareTo(bRaw.length);
      } else {
        if (aRaw != bRaw) return aRaw.compareTo(bRaw);
      }
    }
    
    if (aMatches.length != bMatches.length) {
      return aMatches.length.compareTo(bMatches.length);
    }
    
    return a.compareTo(b);
  }

  /// Robust method to get audiobook details with isolated error handling and timeouts
  Future<Audiobook> getAudiobookDetails(String folderPath) async {
    List<Chapter> chapters = [];
    Duration totalDuration = Duration.zero;
    Uint8List? coverArt;
    String? author;
    String? album;
    String? year;
    String? narrator;
    String? description;

    try {
      final List<String> audioFilePaths = [];
      final List<String> imageFilePaths = [];

      // Collect files using NativeScanner with a small retry to handle OS/SAF indexing lag
      var entities = await NativeScanner.listDirectory(folderPath);
      if (entities.isEmpty) {
        _logDebug("  listDirectory returned empty, retrying in 500ms...");
        await Future.delayed(const Duration(milliseconds: 500));
        entities = await NativeScanner.listDirectory(folderPath);
      }
      
      final List<String> cueFilePaths = [];
      
      for (final entity in entities) {
        try {
          if (!entity.isDirectory) {
            final fileName = entity.name;
            final extension = p.extension(fileName).toLowerCase();
            
            if (fileName.toLowerCase() == '.nomedia' || 
                fileName == '.DS_Store' || 
                fileName.toLowerCase() == 'thumbs.db') {
              continue;
            }

            if (_supportedFormats.contains(extension)) {
              audioFilePaths.add(entity.path);
            } else if (_coverArtFormats.contains(extension)) {
              imageFilePaths.add(entity.path);
            } else if (extension == '.cue') {
              cueFilePaths.add(entity.path);
            }
          }
        } catch (e) {
          _logDebug("  Skipping unreadable entity in $folderPath: $e");
        }
      }

      if (audioFilePaths.isEmpty) {
        return _createEmptyAudiobook(folderPath);
      }

      // Sort by filename (not full path) for consistent alphanumeric order
      audioFilePaths.sort((a, b) => _naturalCompare(p.basename(a), p.basename(b)));

      // COVER ART SELECTION CHAIN (Chain of Thought)
      // 1. Check if user has explicitly selected a cover (Final Boss)
      final bool userHasSelectedCover = await StorageService().hasManualCover(folderPath);
      
      if (userHasSelectedCover) {
        _logDebug("  User has manually selected a cover for this book. Loading from cache (Final Boss).");
        coverArt = await StorageService().loadCachedCoverArt(folderPath);
      }
      
      // 2. If no manual cover, try local folder FIRST (higher quality/faster)
      if (coverArt == null && imageFilePaths.isNotEmpty) {
        _logDebug("  Searching local folder for cover images...");
        coverArt = await _tryLoadImageCover(imageFilePaths);
        if (coverArt != null && coverArt!.isNotEmpty) {
          _logDebug("  Found cover in local folder.");
          await StorageService().saveCachedCoverArt(folderPath, coverArt!);
          
          // Ensure it exists as EmbeddedCover.jpg but don't overwrite
          final bool hasExistingCover = entities.any((e) => !e.isDirectory && 
              (e.name.toLowerCase() == 'cover.jpg' || e.name.toLowerCase() == 'embeddedcover.jpg'));
          if (!hasExistingCover) {
            await NativeScanner.writeBytes(folderPath, coverArt!, fileName: 'EmbeddedCover.jpg');
          }
        }
      }

      // 2.5 Try to parse .cue file if present
      CueMetadata? cueMetadata;
      if (cueFilePaths.isNotEmpty) {
        _logDebug("  Found .cue file(s), attempting to parse: ${cueFilePaths.first}");
        cueMetadata = await CueParser.parse(cueFilePaths.first, folderPath);
        if (cueMetadata != null) {
          _logDebug("  Successfully parsed .cue file with ${cueMetadata.tracks.length} tracks.");
          if (author == null && cueMetadata.performer != null) {
            author = cueMetadata.performer;
          }
        }
      }

      // 3. MANDATORY: Process audio files for chapters, duration, and author
      // This ALSO acts as the fall-back for embedded cover art
      // PERFORMANCE FIX: Only extract cover from audio if we DON'T have a local one.
      // 3. MANDATORY: Process audio files for chapters, duration, and author
      // OPTIMIZATION: Process files in parallel batches to speed up loading
      final audioPlayer = AudioPlayer(); // We still need this for just_audio fallback
      final bool hasPhysicalCover = entities.any((e) => !e.isDirectory && 
          (e.name.toLowerCase() == 'cover.jpg' || e.name.toLowerCase() == 'embeddedcover.jpg'));
      
      try {
        // PERFORMANCE FIX: Process files sequentially to avoid AudioPlayer state collisions.
        // Parallel batching was causing 'abort' errors in just_audio during metadata fallback.
        for (final filePath in audioFilePaths) {
           final shouldExtractCover = coverArt == null && !hasPhysicalCover;
           final result = await _processAudioFileRobust(
              filePath, 
              folderPath, 
              audioPlayer, 
              extractCoverArt: shouldExtractCover, 
              extractAuthor: author == null,
              forceFfmpegCover: !hasPhysicalCover && coverArt == null && p.extension(filePath).toLowerCase() == '.m4b',
              audioFileCount: audioFilePaths.length,
           );
          
          if (result != null) {
            // If we have CUE metadata for this specific file, use that instead of generic chapters
            bool usedCue = false;
            if (cueMetadata != null) {
              final baseName = p.basename(filePath).toLowerCase();
              final fileHasCueTracks = cueMetadata.tracks.any((t) => 
                t.fileName.toLowerCase() == baseName || 
                p.basenameWithoutExtension(t.fileName).toLowerCase() == p.basenameWithoutExtension(baseName)
              );

              if (fileHasCueTracks) {
                final cueChapters = CueParser.convertToChapters(
                  cueMetadata, 
                  folderPath, 
                  [filePath], 
                  result.chapters.fold(Duration.zero, (prev, element) => prev + (element.duration ?? Duration.zero))
                );
                
                if (cueChapters.isNotEmpty) {
                  _logDebug("  Applying ${cueChapters.length} .cue chapters to ${p.basename(filePath)}");
                  chapters.addAll(cueChapters);
                  for (var chapter in cueChapters) {
                     totalDuration += chapter.duration ?? Duration.zero;
                  }
                  usedCue = true;
                }
              }
            }

            if (!usedCue) {
              chapters.addAll(result.chapters);
              for (var chapter in result.chapters) {
                 totalDuration += chapter.duration ?? Duration.zero;
              }
            }
            
            if (author == null && result.author != null) author = result.author;
            if (album == null && result.album != null) album = result.album;
            if (year == null && result.year != null) year = result.year;
            if (narrator == null && result.narrator != null) narrator = result.narrator;
            if (description == null && result.description != null) description = result.description;
            
            // Capture embedded cover
            if (result.coverArt != null && result.coverArt!.isNotEmpty) {
              if (coverArt == null) {
                _logDebug("  Found embedded cover art in a chapter file");
                coverArt = result.coverArt;
                await StorageService().saveCachedCoverArt(folderPath, coverArt!);
              }

              if (!hasPhysicalCover) {
                 // Save physically but don't await/block
                 NativeScanner.writeBytes(folderPath, result.coverArt!, fileName: 'EmbeddedCover.jpg')
                    .then((_) => _logDebug("  Background: Extracted local cover"))
                    .catchError((e) => null);
              }
            }
          }
        }
      } finally {
        await audioPlayer.dispose();
      }

      // 4. Final Cache Fallback & Persistence
      if (coverArt == null) {
        coverArt = await StorageService().loadCachedCoverArt(folderPath);
      }
      
      // ENSURE PHYSICAL COVER: If we have coverArt but no physical file, save it now
      if (coverArt != null && !hasPhysicalCover) {
        try {
          await NativeScanner.writeBytes(folderPath, coverArt!, fileName: 'EmbeddedCover.jpg');
          _logDebug("  Ensured physical cover exists: $folderPath/EmbeddedCover.jpg");
        } catch (e) {
          _logDebug("  Failed to save physical cover: $e");
        }
      }
      
      final displayName = await NativeScanner.getDisplayName(folderPath);
      String bookTitle = _cleanTitle(displayName ?? p.basename(folderPath));

      // USER REQUEST: Prioritize metadata title (Album tag or Title tag)
      if (audioFilePaths.isNotEmpty) {
        try {
          if (cueMetadata != null && cueMetadata.album != null && cueMetadata.album!.isNotEmpty) {
            _logDebug("  Using .cue Album for book title: ${cueMetadata.album}");
            bookTitle = cueMetadata.album!;
          } else {
            // We can use the information from the first file to set the book title
            final firstFileRet = await NativeScanner.getMetadata(audioFilePaths.first, extractCover: false);
            if (firstFileRet != null) {
              final album = firstFileRet['album'] as String?;
              final tagTitle = firstFileRet['title'] as String?;
              
              if (audioFilePaths.length == 1) {
                if (album != null && album.trim().isNotEmpty) {
                  _logDebug("  Single file: Using Album tag for book title: $album");
                  bookTitle = album.trim();
                } else if (tagTitle != null && tagTitle.trim().isNotEmpty) {
                  _logDebug("  Single file: Using Title tag for book title: $tagTitle");
                  bookTitle = tagTitle.trim();
                }
              }
            }
          }
        } catch (e) {
          _logDebug("  Error extracting title priority: $e");
        }
      }
      
      // USER REQUEST: Consistency for single-file books (Chapter Title = Book Title)
      if (chapters.length == 1 && chapters.first.title == p.basenameWithoutExtension(_cleanTitle(audioFilePaths.first))) {
         chapters[0] = chapters[0].copyWith(title: bookTitle);
      }
      
      return Audiobook(
        id: folderPath,
        title: bookTitle, // AudiobookProvider will handle using customTitles if valid
        author: author,
        album: album,
        year: year,
        description: description,
        narrator: narrator,
        chapters: chapters,
        totalDuration: totalDuration,
        coverArt: coverArt,
      );

    } catch (e) {
      _logDebug("Critical error processing folder $folderPath: $e");
      return _createEmptyAudiobook(folderPath);
    }
  }

  /// Helper to create a basic empty audiobook on failure
  Audiobook _createEmptyAudiobook(String folderPath) {
    return Audiobook(
      id: folderPath,
      title: p.basename(folderPath),
      author: null,
      chapters: [],
      totalDuration: Duration.zero,
    );
  }

  /// Robust metadata processing for a single audio file
  Future<_ChapterProcessingResult?> _processAudioFileRobust(
    String filePath,
    String folderPath,
    AudioPlayer audioPlayer, {
    bool extractCoverArt = true,
    bool extractAuthor = true,
    bool forceFfmpegCover = false,
    int audioFileCount = 1,
  }) async {
    final fileName = _cleanTitle(filePath);
    String chapterTitle = p.basenameWithoutExtension(fileName);
    Duration? chapterDuration;
    Uint8List? coverArt;
    String? author;
    Map<String, dynamic>? retrieverMetadata;

    // STEP 1: Try Native Metadata Extraction (Preferred for SAF Uris)
    if (filePath.startsWith('content://')) {
      try {
        final nativeMetadata = await NativeScanner.getMetadata(
          filePath, 
          extractCover: extractCoverArt
        ).timeout(const Duration(seconds: 10));

        if (nativeMetadata != null) {
          retrieverMetadata = nativeMetadata;
          if (audioFileCount == 1) {
            chapterTitle = nativeMetadata['title'] ?? chapterTitle;
          }
          author = nativeMetadata['artist'] ?? nativeMetadata['albumArtist'];
          
          if (nativeMetadata['duration'] != null) {
            chapterDuration = Duration(milliseconds: (nativeMetadata['duration'] as num).toInt());
          }
          
          if (extractCoverArt && nativeMetadata['coverArt'] != null) {
            coverArt = nativeMetadata['coverArt'] as Uint8List;
            _logDebug("  Cover art extracted via NativeScanner for $fileName");
          }
        }
      } catch (e) {
        _logDebug("Native metadata failed for $fileName: $e");
      }
    } else {
      // Non-SAF path: Still try NativeScanner, it handles direct paths too
      try {
        final nativeMetadata = await NativeScanner.getMetadata(
          filePath, 
          extractCover: extractCoverArt
        ).timeout(const Duration(seconds: 30));
        
        if (nativeMetadata != null) {
          retrieverMetadata = nativeMetadata;
          if (audioFileCount == 1) {
            chapterTitle = nativeMetadata['title'] ?? chapterTitle;
          }
          author = nativeMetadata['artist'] ?? nativeMetadata['albumArtist'];
          
          if (nativeMetadata['duration'] != null) {
            chapterDuration = Duration(milliseconds: (nativeMetadata['duration'] as num).toInt());
          }
          
          if (extractCoverArt && nativeMetadata['coverArt'] != null) {
            coverArt = nativeMetadata['coverArt'] as Uint8List;
            _logDebug("  Cover art extracted via NativeScanner (Local) for $fileName");
          }
        } else {
          _logDebug("  NativeScanner returned null metadata for $fileName");
        }
      } catch (e) {
        _logDebug("Native metadata (Local) failed for $fileName: $e");
      }
    }

    // STEP 2: FFmpeg Cover Art Fallback
    if (extractCoverArt && coverArt == null) {
      try {
        final ffmpegCover = await FFmpegHelper.extractCoverArt(filePath: filePath)
            .timeout(const Duration(seconds: 20));
        if (ffmpegCover != null && ffmpegCover.isNotEmpty) {
          coverArt = ffmpegCover;
          _logDebug("  Cover art extracted via FFmpeg fallback for $fileName");
        }
      } catch (e) {
        _logDebug("FFmpeg cover extraction failed for $fileName: $e");
      }
    }

    // STEP 3: Duration with just_audio (Works for both Files and Uris)
    if (chapterDuration == null || chapterDuration == Duration.zero) {
      try {
        Duration? durationOrNull;
        if (filePath.startsWith('content://')) {
          durationOrNull = await audioPlayer.setAudioSource(AudioSource.uri(Uri.parse(filePath)))
              .timeout(const Duration(seconds: 15));
        } else {
          durationOrNull = await audioPlayer.setFilePath(filePath)
              .timeout(const Duration(seconds: 15));
        }
        
        if (durationOrNull != null && durationOrNull > Duration.zero) {
          chapterDuration = durationOrNull;
        }
      } catch (e) {
        _logDebug("just_audio failed for $fileName: $e");
      }
    }

    if (chapterDuration == null || chapterDuration == Duration.zero) {
      return null;
    }

    List<Chapter>? finalChapters;
    // USER REQUEST: For multi-file books, stick to file names. 
    // Only search for embedded chapters if it's a single-file book.
    if (audioFileCount == 1 && chapterDuration > const Duration(minutes: 10)) {
       try {
         final embeddedChapters = await FFmpegHelper.extractChapters(
           filePath: filePath, 
           audiobookId: folderPath
         ).timeout(const Duration(seconds: 15));
         
         if (embeddedChapters.isNotEmpty) {
           _logDebug("Found ${embeddedChapters.length} embedded chapters in $fileName");
           
           // USER FIX: Ensure chapters cover the full file duration
           final List<Chapter> filledChapters = [];
           Duration currentPos = Duration.zero;
           
           for (int i = 0; i < embeddedChapters.length; i++) {
             final ch = embeddedChapters[i];
             
             // If there's a gap before this chapter, fill it
             if (ch.start > currentPos + const Duration(seconds: 2)) {
               filledChapters.add(Chapter(
                 id: "${filePath}_gap_$i",
                 title: i == 0 ? "Introduction" : "Chapter ${i} (Cont.)",
                 audiobookId: folderPath,
                 sourcePath: filePath,
                 start: currentPos,
                 end: ch.start,
                 duration: ch.start - currentPos,
               ));
             }
             
             filledChapters.add(ch);
             currentPos = ch.end ?? currentPos;
           }
           
           // If there's a gap after the last chapter, fill it
           if (currentPos < chapterDuration - const Duration(seconds: 2)) {
             filledChapters.add(Chapter(
               id: "${filePath}_gap_end",
               title: "Chapter ${embeddedChapters.length} (Cont.)",
               audiobookId: folderPath,
               sourcePath: filePath,
               start: currentPos,
               end: chapterDuration,
               duration: chapterDuration - currentPos,
             ));
           }
           
           finalChapters = filledChapters;
         }
       } catch (e) {
         _logDebug("FFmpeg chapter extraction failed for $fileName: $e");
       }
    }

    // STEP 5: Supplementary tags via FFmpeg for rich metadata info
    String? year = retrieverMetadata?['date'] as String?;
    String? narrator = retrieverMetadata?['composer'] as String? ?? 
                       retrieverMetadata?['writer'] as String? ?? 
                       retrieverMetadata?['author'] as String?;
    String? description;

    // Use FFmpeg for extended tags if it's an M4B or single file
    if (p.extension(filePath).toLowerCase() == '.m4b' || audioFileCount <= 2) {
      final extendedTags = await FFmpegHelper.getExtendedMetadata(filePath: filePath);
      narrator ??= extendedTags['composer'] ?? extendedTags['writer'] ?? extendedTags['narrator'];
      description = extendedTags['comment'] ?? extendedTags['description'] ?? extendedTags['synopsis'];
      year ??= extendedTags['date'] ?? extendedTags['creation_time'];
    }

    return _ChapterProcessingResult(
      chapters: finalChapters ?? [
        Chapter(
          id: filePath,
          title: chapterTitle,
          audiobookId: folderPath,
          sourcePath: filePath,
          duration: chapterDuration,
          start: Duration.zero,
          end: chapterDuration,
        )
      ],
      coverArt: coverArt,
      author: author,
      album: retrieverMetadata?['album'] as String?,
      metadataTitle: retrieverMetadata?['title'] as String?,
      year: year,
      narrator: narrator,
      description: description,
    );
  }

  /// Helper to try loading cover art from local image files
  Future<Uint8List?> _tryLoadImageCover(List<String> imageFilePaths) async {
    // PRE-SORT: Prioritize filenames containing 'cover', 'folder', 'artwork'
    imageFilePaths.sort((a, b) {
      final nameA = p.basename(a).toLowerCase();
      final nameB = p.basename(b).toLowerCase();
      
      int scoreA = 0;
      // EXACT MATCH PRIORITY (User Request: avoid conflicting images)
      if (nameA == 'cover.jpg' || nameA == 'cover.jpeg') scoreA += 10;
      else if (nameA.contains('cover')) scoreA += 5;
      else if (nameA.contains('folder')) scoreA += 3;
      else if (nameA.contains('artwork')) scoreA += 2;
      else if (nameA == 'embeddedcover.jpg') scoreA += 1; // Lowest priority for local files
      
      int scoreB = 0;
      if (nameB == 'cover.jpg' || nameB == 'cover.jpeg') scoreB += 10;
      else if (nameB.contains('cover')) scoreB += 5;
      else if (nameB.contains('folder')) scoreB += 3;
      else if (nameB.contains('artwork')) scoreB += 2;
      else if (nameB == 'embeddedcover.jpg') scoreB += 1;
      
      if (scoreA != scoreB) return scoreB.compareTo(scoreA); // Descending score
      return _naturalCompare(nameA, nameB);
    });

    // Strategy: Only return the BEST candidate found to avoid loading multiples
    if (imageFilePaths.isNotEmpty) {
      final bestPath = imageFilePaths.first;
      try {
        _logDebug("  Loading best local cover candidate: ${p.basename(bestPath)}");
        final data = await NativeScanner.readBytes(bestPath).timeout(const Duration(seconds: 5));
        if (data != null && data.isNotEmpty) return data;
      } catch (e) {
        _logDebug("  Error reading best image: $e");
      }
    }
    
    return null;
  }

  /// Support for background info loading
  Future<Audiobook> getBasicAudiobookInfo(String folderPath) async {
    try {
      final List<String> audioFilePaths = [];
      final List<String> imageFilePaths = [];
      final List<String> cueFilePaths = [];
      String? author;
      
      final entities = await NativeScanner.listDirectory(folderPath);
      for (final entity in entities) {
        try {
          if (!entity.isDirectory) {
            final fileName = entity.name;
            final extension = p.extension(fileName).toLowerCase();
            
            if (fileName.toLowerCase() == '.nomedia' || 
                fileName == '.DS_Store' || 
                fileName.toLowerCase() == 'thumbs.db') {
              continue;
            }

            if (_supportedFormats.contains(extension)) {
              audioFilePaths.add(entity.path);
            } else if (['.jpg', '.jpeg', '.png', '.webp'].contains(extension)) {
              imageFilePaths.add(entity.path);
            } else if (extension == '.cue') {
              cueFilePaths.add(entity.path);
            }
          }
        } catch (e) {
          _logDebug("  Error scanning basic info: $e");
        }
      }

      if (audioFilePaths.isEmpty) {
        return _createEmptyAudiobook(folderPath);
      }

      audioFilePaths.sort((a, b) => _naturalCompare(p.basename(a), p.basename(b)));

      // Try to parse .cue file if present
      CueMetadata? cueMetadata;
      if (cueFilePaths.isNotEmpty) {
        cueMetadata = await CueParser.parse(cueFilePaths.first, folderPath);
        if (cueMetadata != null) {
          if (author == null && cueMetadata.performer != null) {
            author = cueMetadata.performer;
          }
        }
      }

      final List<Chapter> basicChapters = audioFilePaths.map((path) {
        final fileName = _cleanTitle(path);
        String title = p.basenameWithoutExtension(fileName);
        
        // If there's only one file and it doesn't have a specific title yet, 
        // it will be replaced by the bookTitle later in this method.
        
        return Chapter(
          id: path,
          title: title,
          audiobookId: folderPath,
          sourcePath: path,
          duration: Duration.zero, 
        );
      }).toList();

      final displayName = await NativeScanner.getDisplayName(folderPath);
      String bookTitle = _cleanTitle(displayName ?? p.basename(folderPath));

      if (cueMetadata != null && cueMetadata.album != null && cueMetadata.album!.isNotEmpty) {
        bookTitle = cueMetadata.album!;
      }

      Uint8List? coverArt;

      // COVER ART SELECTION CHAIN
      // 1. Check for manual selection (Final Boss)
      if (await StorageService().hasManualCover(folderPath)) {
        coverArt = await StorageService().loadCachedCoverArt(folderPath);
      }

      // 2. Try Local Folder FIRST (Quality & Performance)
      if (coverArt == null && imageFilePaths.isNotEmpty) {
        coverArt = await _tryLoadImageCover(imageFilePaths);
      }

      // 3. Fallback to Embedded Metadata
      // PERFORMANCE FIX: ONLY extract from audio if we truly lack a cover art.
      // Do NOT "prime" folders for 700MB+ books if we already have a local image.
      final bool hasPhysicalCover = entities.any((e) => !e.isDirectory && 
          (e.name.toLowerCase() == 'cover.jpg' || e.name.toLowerCase() == 'embeddedcover.jpg'));
      
      if (coverArt == null) {
        try {
          final metadata = await NativeScanner.getMetadata(audioFilePaths.first, extractCover: true)
              .timeout(const Duration(seconds: 30));
          if (metadata != null) {
            author = author ?? metadata['artist'] ?? metadata['albumArtist'];
            
            final album = metadata['album'] as String?;
            final tagTitle = metadata['title'] as String?;
            
            if (audioFilePaths.length == 1) {
              if (album != null && album.trim().isNotEmpty) {
                bookTitle = album.trim();
              } else if (tagTitle != null && tagTitle.trim().isNotEmpty) {
                bookTitle = tagTitle.trim();
              }
            }
            
            if (metadata['coverArt'] != null && (metadata['coverArt'] as Uint8List).isNotEmpty) {
              final embeddedData = metadata['coverArt'] as Uint8List;
              if (coverArt == null) {
                coverArt = embeddedData;
              }
              
              if (!hasPhysicalCover) {
                await NativeScanner.writeBytes(folderPath, embeddedData, fileName: 'EmbeddedCover.jpg');
                _logDebug("  Persisted extracted cover art to folder: $folderPath");
              }
            }
          }
        } catch (e) {
          _logDebug("  Initial metadata extraction failed: $e");
        }
      }

      // 4. Final Cache Fallback
      if (coverArt == null) {
        coverArt = await StorageService().loadCachedCoverArt(folderPath);
      }

      // USER REQUEST: Consistency for single-file books
      if (basicChapters.length == 1 && basicChapters.first.title == p.basenameWithoutExtension(_cleanTitle(audioFilePaths.first))) {
         // This is a bit tricky since basicChapters is a List and we return it.
         // We'll create a new list with a modified chapter.
         final updatedChapters = [
           basicChapters.first.copyWith(title: bookTitle)
         ];
         return Audiobook(
           id: folderPath,
           title: bookTitle,
           author: author,
           coverArt: coverArt,
           chapters: updatedChapters,
           totalDuration: Duration.zero,
         );
      }

      return Audiobook(
        id: folderPath,
        title: bookTitle,
        author: author,
        coverArt: coverArt,
        chapters: basicChapters,
        totalDuration: Duration.zero,
      );
    } catch (e) {
      _logDebug("Error in basic info for $folderPath: $e");
      return _createEmptyAudiobook(folderPath);
    }
  }

  /// Loads detailed metadata on-demand
  Future<Audiobook> loadDetailedMetadata(Audiobook basicBook) async {
    return getAudiobookDetails(basicBook.id);
  }

  /// Batch load basic info
  Future<List<Audiobook>> loadBasicInfoBatch(List<String> folderPaths, {int batchSize = 5}) async {
    final List<Audiobook> results = [];
    for (int i = 0; i < folderPaths.length; i += batchSize) {
      final batch = folderPaths.sublist(i, (i + batchSize).clamp(0, folderPaths.length));
      final futures = batch.map((path) => getBasicAudiobookInfo(path));
      final batchResults = await Future.wait(futures);
      results.addAll(batchResults.where((book) => book.chapters.isNotEmpty));
    }
    return results;
  }

  /// Extract potential tags from folder hierarchy
  List<String> extractPotentialTags(String audiobookPath, String rootPath) {
    final List<String> potentialTags = [];
    try {
      if (audiobookPath.startsWith('content://')) {
          // For SAF URIs, we try to extract segments from the document ID
          final uri = Uri.parse(audiobookPath);
          String? docId;
          
          if (audiobookPath.contains('/document/')) {
            docId = Uri.decodeFull(audiobookPath.split('/document/').last);
          } else if (audiobookPath.contains('/tree/')) {
             docId = Uri.decodeFull(audiobookPath.split('/tree/').last);
          }

          if (docId != null) {
            // Document IDs often look like "PRIMARY:Folder/Subfolder/BookFolder"
            final segments = docId.split(RegExp(r'[:/]'))
                .where((s) => s.isNotEmpty && s.toUpperCase() != "PRIMARY")
                .toList();
            
            if (segments.isNotEmpty) {
              segments.removeLast(); // The last segment is the book folder itself
            }
            
            // USER REQUEST: Do not make a tag out of the root folder.
            // If the root was selected at "Audiobooks", and we are at "Audiobooks/Fantasy/Book",
            // the segments are ["Audiobooks", "Fantasy"].
            // We should ideally skip "Audiobooks" if it's the top-most segment of the rootPath.
            
            // For now, let's at least skip the first segment if there are multiple, 
            // as the first segment is usually the root of the picked tree.
            if (segments.length > 1) {
              segments.removeAt(0);
            } else if (segments.length == 1) {
              // If only one segment remains, and it's the root, skip it
              segments.clear();
            }
            
            for (final segment in segments) {
               final cleaned = segment.trim();
               if (cleaned.isNotEmpty && cleaned.length > 2) {
                  potentialTags.add(cleaned);
               }
            }
          }
          return potentialTags;
      }

      final relativePath = p.relative(audiobookPath, from: rootPath);
      final pathSegments = p.split(relativePath);
      if (pathSegments.isNotEmpty) {
        pathSegments.removeLast(); // Remove book folder
      }
      
      // USER REQUEST: Skip root folder
      if (pathSegments.isNotEmpty) {
        // p.relative doesn't include the root folder name itself, 
        // it starts from inside the root. So splitting relativePath 
        // ALREADY excludes the root folder.
      }
      
      for (final segment in pathSegments) {
        final cleanedSegment = segment.trim();
        if (cleanedSegment.isNotEmpty && cleanedSegment.length > 2) {
          potentialTags.add(cleanedSegment);
        }
      }
    } catch (e) {
      _logDebug("Error extracting tags: $e");
    }
    return potentialTags;
  }

  List<String> suggestTagNames(List<String> audiobookPaths, String rootPath) {
    final Map<String, int> tagCounts = {};
    for (final path in audiobookPaths) {
      final tags = extractPotentialTags(path, rootPath);
      for (final tag in tags) {
        tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
      }
    }
    
    // Only suggest tags that appear for multiple books to avoid clutter
    return tagCounts.entries
        .where((e) => e.value >= 1) // In this app, even 1 is fine for auto-mapping
        .map((e) => e.key)
        .toList();
  }

  /// Robustly cleans a title string, specially handling SAF URIs.
  String _cleanTitle(String title) {
    if (title.isEmpty) return "Unknown";
    
    // Check if it's likely a SAF encoded string
    if (title.contains('%3A') || title.contains('%2F') || title.contains(':')) {
      try {
        // 1. Full URL Decode
        String decoded = Uri.decodeFull(title);
        
        // 2. Handle Document ID pattern (primary:Folder/Sub/Book)
        if (decoded.contains(':')) {
          decoded = decoded.split(':').last;
        }
        
        // 3. Extraction of the last segment (the actual folder name)
        if (decoded.contains('/')) {
          final segments = decoded.split('/').where((s) => s.trim().isNotEmpty).toList();
          if (segments.isNotEmpty) {
            return segments.last;
          }
        }
        
        return decoded.trim().isNotEmpty ? decoded.trim() : title;
      } catch (e) {
        // Fallback for failed decode
        return title.split('/').last.split(':').last;
      }
    }
    
    return title;
  }
}

class _ChapterProcessingResult {
  final List<Chapter> chapters; // Changed to list to support embedded chapters
  final Uint8List? coverArt;
  final String? author;
  final String? album;
  final String? metadataTitle;
  final String? year;
  final String? description;
  final String? narrator;

  _ChapterProcessingResult({
    required this.chapters,
    this.coverArt,
    this.author,
    this.album,
    this.metadataTitle,
    this.year,
    this.description,
    this.narrator,
  });
}
