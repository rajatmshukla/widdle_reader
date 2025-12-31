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

      // 1. Get media information to check specifically for video/image streams
      final session = await FFprobeKit.getMediaInformation(actualPath);
      final information = session.getMediaInformation();
      if (information == null) return null;

      final streams = information.getStreams();
      bool hasAttachedPic = false;
      for (final stream in streams) {
        final type = stream.getType();
        // In audio files, a video stream is almost always the embedded cover art
        if (type == 'video') {
          hasAttachedPic = true;
          break;
        }
      }

      if (!hasAttachedPic) {
        debugPrint("FFmpeg: No video/attached_pic streams found in $filePath");
        return null;
      }

      // 2. Use FFmpeg to extract the first video stream to a temporary file
      // -i input -map 0:v -c copy -frames:v 1 -f image2 out.jpg
      final tempFile = File('${Directory.systemTemp.path}/ffmpeg_cover_${DateTime.now().millisecondsSinceEpoch}.jpg');
      
      // We use -map 0:v:0 to get the first video stream (usually the cover)
      // -vframes 1 to get only one frame
      // -q:v 2 for high quality if re-encoding is needed, but -c:v copy is better if it's already mjpeg/png
      final command = '-i "$actualPath" -map 0:v:0 -c:v copy -frames:v 1 -f image2 "${tempFile.path}" -y';
      
      final ffSession = await FFmpegKit.execute(command);
      final returnCode = await ffSession.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        if (await tempFile.exists()) {
          final bytes = await tempFile.readAsBytes();
          // Clean up
          try { await tempFile.delete(); } catch (_) {}
          debugPrint("FFmpeg: Successfully extracted ${bytes.length} bytes of cover art");
          return bytes;
        }
      } else {
        debugPrint("FFmpeg: Cover extraction command failed with code $returnCode");
        // Fallback: Try without -c:v copy in case the format needs re-encoding to jpg
        final fallbackCommand = '-i "$actualPath" -map 0:v:0 -frames:v 1 -f image2 "${tempFile.path}" -y';
        final fallbackSession = await FFmpegKit.execute(fallbackCommand);
        if (ReturnCode.isSuccess(await fallbackSession.getReturnCode())) {
           if (await tempFile.exists()) {
             final bytes = await tempFile.readAsBytes();
             try { await tempFile.delete(); } catch (_) {}
             debugPrint("FFmpeg: Successfully extracted ${bytes.length} bytes (with re-encode)");
             return bytes;
           }
        }
      }
    } catch (e) {
      debugPrint("Error extracting cover art with FFmpeg: $e");
    }
    return null;
  }
}
