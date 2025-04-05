import 'dart:typed_data';
import 'chapter.dart';

class Audiobook {
  final String id; // Use folder path as unique ID
  final String title;
  final List<Chapter> chapters;
  Duration totalDuration;
  Uint8List? coverArt; // Store cover art data

  Audiobook({
    required this.id,
    required this.title,
    required this.chapters,
    this.totalDuration = Duration.zero,
    this.coverArt,
  });
}
