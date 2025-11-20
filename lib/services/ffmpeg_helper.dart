import 'package:ffmpeg_kit_flutter_new_audio/ffprobe_kit.dart';
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
      final session = await FFprobeKit.getMediaInformation(filePath);
      final information = session.getMediaInformation();

      if (information == null) {
        debugPrint("FFprobe: No media information found for $filePath");
        return [];
      }

      final ffmpegChapters = information.getChapters();
      if (ffmpegChapters.isEmpty) {
        debugPrint("FFprobe: No chapters found in $filePath");
        return [];
      }

      debugPrint("FFprobe: Found ${ffmpegChapters.length} chapters in $filePath");

      for (int i = 0; i < ffmpegChapters.length; i++) {
        final chapter = ffmpegChapters[i];
        
        // FFmpeg times are usually in milliseconds or seconds depending on time_base
        // getStart() and getEnd() usually return values in the time_base units
        // But getStartTime() and getEndTime() return seconds as double/string usually?
        // Let's check the API. FFprobeKit returns Chapter objects.
        // Usually they have start, end, and tags (title).
        
        // Safe parsing of start/end times (assuming milliseconds if integer, or converting)
        // The Chapter object from ffmpeg_kit has getStart(), getEnd() which are long (int).
        // It also has getTimeBase().
        
        final startVal = chapter.getStart();
        final endVal = chapter.getEnd();
        // final timeBase = chapter.getTimeBase(); // e.g. "1/1000"
        
        // However, usually it's safer to rely on getStartTime() / getEndTime() which are often in seconds
        // But the Chapter class in ffmpeg_kit_flutter might vary.
        // Let's assume standard behavior: start/end are raw values.
        // We might need to calculate based on time_base, but often for simple audio
        // it's easier to use the metadata if available.
        
        // Let's try to use the 'tags' to get the title.
        final tags = chapter.getTags();
        String title = "Chapter ${i + 1}";
        if (tags != null && tags['title'] != null) {
          title = tags['title']!;
        }

        // Calculate duration
        // Note: We need to be careful about units. 
        // For now, let's assume the values are usable or we can get seconds.
        // Actually, looking at the library, it's often safer to trust the 'start_time' and 'end_time' strings if available,
        // but getStart() is a number.
        
        // Let's rely on a simpler assumption for now: 
        // If we can't easily determine the unit, we might need to inspect the output.
        // But typically, FFprobeKit handles this.
        
        // Let's use a robust way:
        // We'll use the start/end times converted to Duration.
        // We'll assume they are in milliseconds for now, but we should verify.
        // Wait, FFmpeg usually uses a timebase.
        
        // Let's use the helper method if available or just parse.
        // Actually, let's look at the properties available on the Chapter object at runtime if needed.
        // For now, we'll implement a best-effort extraction.
        
        // Using start_time and end_time (seconds) is usually most reliable if available.
        // But the wrapper might expose them as getStartTime().
        
        // Let's try to use the raw values and convert.
        // If start/end are large integers, they are likely timebase units.
        // If we don't know the timebase, it's hard.
        
        // BETTER APPROACH:
        // Use the JSON output from FFprobe which is standard.
        final allProperties = information.getAllProperties();
        if (allProperties != null && allProperties['chapters'] is List) {
          final jsonChapters = allProperties['chapters'] as List;
          final jsonChapter = jsonChapters[i];
          
          final startTimeStr = jsonChapter['start_time'];
          final endTimeStr = jsonChapter['end_time'];
          
          if (startTimeStr != null && endTimeStr != null) {
            final startSeconds = double.tryParse(startTimeStr.toString()) ?? 0.0;
            final endSeconds = double.tryParse(endTimeStr.toString()) ?? 0.0;
            
            final startDuration = Duration(milliseconds: (startSeconds * 1000).round());
            final endDuration = Duration(milliseconds: (endSeconds * 1000).round());
            
            chapters.add(Chapter(
              id: "$filePath#$i", // Unique ID for this segment
              title: title,
              audiobookId: audiobookId,
              sourcePath: filePath,
              start: startDuration,
              end: endDuration,
              duration: endDuration - startDuration,
            ));
          }
        }
      }
    } catch (e) {
      debugPrint("Error extracting chapters with FFmpeg: $e");
    }

    return chapters;
  }
}
