import 'dart:io';
import 'dart:typed_data';
import 'package:ffmpeg_kit_flutter_new_audio/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:flutter/foundation.dart';
import '../models/chapter.dart';

class FFmpegHelper {
  /// Extracts chapters from an audio file using FFprobe.
  /// Returns a list of [Chapter] objects if chapters are found.
  /// Returns an empty list if no chapters are found or an error occurs.
  static Future<List<Chapter>> extractChapters({
    required String filePath,
    required String audiobookId,
  }) async {
    final List<Chapter> chapters = [];

    try {
      debugPrint("FFprobe: Starting extraction for $filePath");
      String actualPath = filePath;
      
      // FFprobeKit (Android) often handles content:// URIs directly.
      // We'll try direct access first, then fallback to getSafParameter if it fails.
      
      var session = await FFprobeKit.getMediaInformation(actualPath);
      var information = session.getMediaInformation();

      if (information == null && filePath.startsWith('content://')) {
        debugPrint("FFprobe: Direct access returned no info, trying SAF parameter...");
        final safPath = await FFmpegKitConfig.getSafParameter(filePath, "r");
        if (safPath != null) {
          actualPath = safPath;
          debugPrint("FFprobe: Using SAF parameter path: $actualPath");
          session = await FFprobeKit.getMediaInformation(actualPath);
          information = session.getMediaInformation();
        }
      }

      if (information == null) {
        debugPrint("FFprobe: No media information found for $filePath after all attempts");
        return [];
      }

      final ffmpegChapters = information.getChapters();
      if (ffmpegChapters.isEmpty) {
        debugPrint("FFprobe: No chapters found in $filePath");
        return [];
      }

      debugPrint("FFprobe: Found ${ffmpegChapters.length} native chapter objects in $filePath");

      final allProperties = information.getAllProperties();
      final List<dynamic>? jsonChapters = (allProperties != null && allProperties['chapters'] is List) 
          ? allProperties['chapters'] as List 
          : null;

      for (int i = 0; i < ffmpegChapters.length; i++) {
        final chapterObj = ffmpegChapters[i];
        
        // 1. Try to get title from tags
        final tags = chapterObj.getTags();
        String title = "Chapter ${i + 1}";
        if (tags != null && tags['title'] != null) {
          title = tags['title']!;
        }

        double startSeconds = 0.0;
        double endSeconds = 0.0;
        
        // 2. Try to use JSON data if available for higher precision (seconds as double)
        bool usedJson = false;
        if (jsonChapters != null && i < jsonChapters.length) {
          final jsonChapter = jsonChapters[i];
          final startTimeStr = jsonChapter['start_time'];
          final endTimeStr = jsonChapter['end_time'];
          
          if (startTimeStr != null && endTimeStr != null) {
            startSeconds = double.tryParse(startTimeStr.toString()) ?? 0.0;
            endSeconds = double.tryParse(endTimeStr.toString()) ?? 0.0;
            usedJson = true;
          }
        }

        // 3. Fallback to native object values if JSON wasn't helpful or available
        if (!usedJson) {
           // Native getStart/getEnd are in time_base units
           final int startVal = chapterObj.getStart() ?? 0;
           final int endVal = chapterObj.getEnd() ?? 0;
           final timeBaseStr = chapterObj.getTimeBase() ?? "1/1000";
           
           if (timeBaseStr.contains('/')) {
             final parts = timeBaseStr.split('/');
             final num = double.tryParse(parts[0]) ?? 1.0;
             final den = double.tryParse(parts[1]) ?? 1000.0;
             startSeconds = startVal * (num / den);
             endSeconds = endVal * (num / den);
           } else {
             startSeconds = startVal / 1000.0;
             endSeconds = endVal / 1000.0;
           }
        }

        final startDuration = Duration(milliseconds: (startSeconds * 1000).round());
        final endDuration = Duration(milliseconds: (endSeconds * 1000).round());
        final chapterDuration = endDuration > startDuration ? endDuration - startDuration : Duration.zero;

        // Only add if duration > 0 OR if it's the only chapter (to be safe)
        if (chapterDuration > Duration.zero || i == 0) {
          chapters.add(Chapter(
            id: "$filePath#$i",
            title: title,
            audiobookId: audiobookId,
            sourcePath: filePath,
            start: startDuration,
            end: endDuration,
            duration: chapterDuration,
          ));
        }
      }
    } catch (e) {
      debugPrint("Error extracting chapters with FFmpeg: $e");
    }

    return chapters;
  }

  /// Extracts embedded cover art from an audio file using FFmpeg.
  /// Returns the image bytes if found, otherwise null.
  static Future<Uint8List?> extractCoverArt({
    required String filePath,
  }) async {
    try {
      debugPrint("FFmpeg: Attempting cover art extraction for $filePath");
      String actualPath = filePath;
      
      if (filePath.startsWith('content://')) {
        final safPath = await FFmpegKitConfig.getSafParameter(filePath, "r");
        if (safPath != null) {
          actualPath = safPath;
        }
      }

      // 2. Use FFmpeg to extract the video stream to a temporary file
      // We try multiple commands for maximum compatibility
      final tempFile = File('${Directory.systemTemp.path}/ffmpeg_cover_${DateTime.now().millisecondsSinceEpoch}.jpg');
      
      // Attempt 1: Fast copy of first video stream
      final cmd1 = '-i "$actualPath" -map 0:v:0 -c:v copy -frames:v 1 -f image2 "${tempFile.path}" -y';
      var ffSession = await FFmpegKit.execute(cmd1);
      if (ReturnCode.isSuccess(await ffSession.getReturnCode()) && await tempFile.exists()) {
        return await _readAndDelete(tempFile);
      }

      // Attempt 2: Re-encode first video stream (safer for different formats)
      final cmd2 = '-i "$actualPath" -map 0:v:0 -frames:v 1 -f image2 "${tempFile.path}" -y';
      ffSession = await FFmpegKit.execute(cmd2);
      if (ReturnCode.isSuccess(await ffSession.getReturnCode()) && await tempFile.exists()) {
        return await _readAndDelete(tempFile);
      }

      // Attempt 3: Auto-detect cover (no explicit map)
      final cmd3 = '-i "$actualPath" -frames:v 1 -f image2 "${tempFile.path}" -y';
      ffSession = await FFmpegKit.execute(cmd3);
      if (ReturnCode.isSuccess(await ffSession.getReturnCode()) && await tempFile.exists()) {
        return await _readAndDelete(tempFile);
      }

      // Attempt 4: Extract using MJPEG format specifically if it's an MP4/M4B
      if (filePath.toLowerCase().endsWith('.m4b') || filePath.toLowerCase().endsWith('.mp4')) {
        final cmd4 = '-i "$actualPath" -map 0:v -vcodec mjpeg -frames:v 1 -f image2 "${tempFile.path}" -y';
        ffSession = await FFmpegKit.execute(cmd4);
        if (ReturnCode.isSuccess(await ffSession.getReturnCode()) && await tempFile.exists()) {
          return await _readAndDelete(tempFile);
        }
      }

    } catch (e) {
      debugPrint("Error extracting cover art with FFmpeg: $e");
    }
    return null;
  }

  static Future<Uint8List?> _readAndDelete(File file) async {
    try {
      final bytes = await file.readAsBytes();
      await file.delete();
      debugPrint("FFmpeg: Successfully extracted ${bytes.length} bytes of cover art");
      return bytes;
    } catch (e) {
      debugPrint("Error reading/deleting temp cover file: $e");
      return null;
    }
  }

  /// Extracts comprehensive metadata tags from an audio file using FFprobe.
  /// This is useful for tags not covered by MediaMetadataRetriever (like 'comment').
  static Future<Map<String, String>> getExtendedMetadata({
    required String filePath,
  }) async {
    try {
      debugPrint("FFprobe: Fetching extended metadata for $filePath");
      String actualPath = filePath;
      
      if (filePath.startsWith('content://')) {
        final safPath = await FFmpegKitConfig.getSafParameter(filePath, "r");
        if (safPath != null) {
          actualPath = safPath;
        }
      }

      final session = await FFprobeKit.getMediaInformation(actualPath);
      final information = session.getMediaInformation();
      if (information == null) return {};

      final tags = information.getTags();
      if (tags == null) return {};

      // Map dynamic to String for consistency
      return tags.map((key, value) => MapEntry(key.toString(), value.toString()));
    } catch (e) {
      debugPrint("Error fetching extended metadata with FFmpeg: $e");
    }
    return {};
  }
}
