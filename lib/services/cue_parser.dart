import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import '../models/chapter.dart';
import 'native_scanner.dart';

class CueMetadata {
  final String? album;
  final String? performer;
  final List<CueTrack> tracks;

  CueMetadata({this.album, this.performer, required this.tracks});
}

class CueTrack {
  final int number;
  final String? title;
  final String? performer;
  final String fileName;
  final Duration startTime;

  CueTrack({
    required this.number,
    this.title,
    this.performer,
    required this.fileName,
    required this.startTime,
  });
}

class CueParser {
  /// Parses a .cue file from a given path (supports SAF content Uris via NativeScanner).
  static Future<CueMetadata?> parse(String cuePath, String folderPath) async {
    try {
      String content;
      if (cuePath.startsWith('content://')) {
        final bytes = await NativeScanner.readBytes(cuePath);
        if (bytes == null) return null;
        try {
          content = utf8.decode(bytes);
        } catch (e) {
          // Fallback to latin1 if utf8 fails
          content = latin1.decode(bytes);
        }
      } else {
        final bytes = await File(cuePath).readAsBytes();
        try {
          content = utf8.decode(bytes);
        } catch (e) {
          content = latin1.decode(bytes);
        }
      }

      return parseString(content, folderPath, cuePath);
    } catch (e) {
      return null;
    }
  }

  /// Parses the raw string content of a .cue file.
  static CueMetadata? parseString(String content, String folderPath, String cuePath) {
    final lines = content.split(RegExp(r'\r?\n'));
    
    String? globalTitle;
    String? globalPerformer;
    String? currentFileName;
    
    final List<CueTrack> tracks = [];
    
    int? currentTrackNumber;
    String? currentTrackTitle;
    String? currentTrackPerformer;
    
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      final parts = _splitLine(line);
      if (parts.isEmpty) continue;

      final command = parts[0].toUpperCase();

      switch (command) {
        case 'TITLE':
          if (currentTrackNumber == null) {
            globalTitle = parts.length > 1 ? _unquote(parts[1]) : null;
          } else {
            currentTrackTitle = parts.length > 1 ? _unquote(parts[1]) : null;
          }
          break;
        case 'PERFORMER':
          if (currentTrackNumber == null) {
            globalPerformer = parts.length > 1 ? _unquote(parts[1]) : null;
          } else {
            currentTrackPerformer = parts.length > 1 ? _unquote(parts[1]) : null;
          }
          break;
        case 'FILE':
          currentFileName = parts.length > 1 ? _unquote(parts[1]) : null;
          break;
        case 'TRACK':
          // If we were already processing a track, it means it didn't have an INDEX 01? 
          // (Usually INDEX comes after TRACK)
          currentTrackNumber = parts.length > 1 ? int.tryParse(parts[1]) : null;
          currentTrackTitle = null;
          currentTrackPerformer = null;
          break;
        case 'INDEX':
          if (currentTrackNumber != null && parts.length > 2) {
            final indexType = parts[1]; // 01 is standard
            if (indexType == '01') {
              final timeStr = parts[2];
              final duration = _parseCueTime(timeStr);
              if (duration != null && currentFileName != null) {
                tracks.add(CueTrack(
                  number: currentTrackNumber!,
                  title: currentTrackTitle,
                  performer: currentTrackPerformer,
                  fileName: currentFileName,
                  startTime: duration,
                ));
              }
            }
          }
          break;
      }
    }

    if (tracks.isEmpty) return null;

    return CueMetadata(
      album: globalTitle,
      performer: globalPerformer,
      tracks: tracks,
    );
  }

  /// Splits a CUE line into parts, respecting quoted strings.
  static List<String> _splitLine(String line) {
    final List<String> parts = [];
    bool inQuote = false;
    StringBuffer currentPart = StringBuffer();

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuote = !inQuote;
        currentPart.write(char);
      } else if (char == ' ' && !inQuote) {
        if (currentPart.isNotEmpty) {
          parts.add(currentPart.toString());
          currentPart.clear();
        }
      } else {
        currentPart.write(char);
      }
    }
    if (currentPart.isNotEmpty) {
      parts.add(currentPart.toString());
    }
    return parts;
  }

  static String _unquote(String s) {
    if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  /// Parses MM:SS:FF format.
  /// MM = Minutes, SS = Seconds, FF = Frames (75 frames per second).
  static Duration? _parseCueTime(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length != 3) return null;

    final minutes = int.tryParse(parts[0]) ?? 0;
    final seconds = int.tryParse(parts[1]) ?? 0;
    final frames = int.tryParse(parts[2]) ?? 0;

    final totalMilliseconds = (minutes * 60 * 1000) + (seconds * 1000) + (frames * 1000 ~/ 75);
    return Duration(milliseconds: totalMilliseconds);
  }

  /// Converts CueTracks into Chapter objects.
  static List<Chapter> convertToChapters(CueMetadata metadata, String folderPath, List<String> audioFiles, Duration totalDuration) {
    final List<Chapter> chapters = [];
    
    for (int i = 0; i < metadata.tracks.length; i++) {
      final track = metadata.tracks[i];
      
      // Find the actual audio file in the folder that matches the track's fileName
      String? matchedPath;
      final cueFileName = track.fileName.toLowerCase();
      
      for (final audioPath in audioFiles) {
        if (p.basename(audioPath).toLowerCase() == cueFileName) {
          matchedPath = audioPath;
          break;
        }
      }

      // If no exact match, try fuzzy match (some .cue files have wrong case or slightly different extension)
      if (matchedPath == null) {
        final cueBaseName = p.basenameWithoutExtension(track.fileName).toLowerCase();
        for (final audioPath in audioFiles) {
          if (p.basenameWithoutExtension(audioPath).toLowerCase() == cueBaseName) {
            matchedPath = audioPath;
            break;
          }
        }
      }

      if (matchedPath == null) continue;

      final start = track.startTime;
      Duration? end;
      
      if (i < metadata.tracks.length - 1) {
        // Next track's start time is this track's end time
        // But only if it's the SAME file. If it refers to a different file, this track goes to the end of the current file.
        if (metadata.tracks[i+1].fileName == track.fileName) {
          end = metadata.tracks[i + 1].startTime;
        } else {
          end = totalDuration;
        }
      } else {
        end = totalDuration;
      }

      final chapterDuration = (end != null && end > start) ? end - start : Duration.zero;

      chapters.add(Chapter(
        id: "$matchedPath#cue${track.number}",
        title: track.title ?? "Track ${track.number}",
        audiobookId: folderPath,
        sourcePath: matchedPath,
        start: start,
        end: end,
        duration: chapterDuration,
      ));
    }

    return chapters;
  }
}
