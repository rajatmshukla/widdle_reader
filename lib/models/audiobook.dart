import 'dart:typed_data';
import 'chapter.dart';
import 'm4b_chapter.dart';

class Audiobook {
  final String id; // Use folder path as unique ID
  final String title;
  final String? author; // Add author field
  final List<Chapter> chapters;
  Duration totalDuration;
  Uint8List? coverArt; // Store cover art data
  
  // M4B-specific properties
  final bool isM4B; // Flag to indicate if this is an M4B audiobook
  final List<M4BChapter>? m4bChapters; // Embedded M4B chapters
  final String? m4bFilePath; // Path to the single M4B file

  Audiobook({
    required this.id,
    required this.title,
    this.author, // Add author parameter to constructor
    required this.chapters,
    this.totalDuration = Duration.zero,
    this.coverArt,
    this.isM4B = false,
    this.m4bChapters,
    this.m4bFilePath,
  });

  /// Get the appropriate chapters list (M4B embedded or traditional file-based)
  List<dynamic> get activeChapters {
    if (isM4B && m4bChapters != null && m4bChapters!.isNotEmpty) {
      return m4bChapters!;
    }
    return chapters;
  }

  /// Get the number of chapters
  int get chapterCount {
    return activeChapters.length;
  }

  /// Check if this audiobook has embedded M4B chapters
  bool get hasEmbeddedChapters {
    return isM4B && m4bChapters != null && m4bChapters!.isNotEmpty;
  }

  /// Get chapter title by index (works with both chapter types)
  String getChapterTitle(int index) {
    final chapters = activeChapters;
    if (index >= 0 && index < chapters.length) {
      final chapter = chapters[index];
      if (chapter is M4BChapter) {
        return chapter.title;
      } else if (chapter is Chapter) {
        return chapter.title;
      }
    }
    return 'Chapter ${index + 1}';
  }

  /// Get chapter duration by index (works with both chapter types)
  Duration? getChapterDuration(int index) {
    final chapters = activeChapters;
    if (index >= 0 && index < chapters.length) {
      final chapter = chapters[index];
      if (chapter is M4BChapter) {
        return chapter.duration;
      } else if (chapter is Chapter) {
        return chapter.duration;
      }
    }
    return null;
  }

  /// Create an M4B audiobook from a single file with embedded chapters
  static Audiobook fromM4BFile({
    required String filePath,
    required String title,
    String? author,
    required List<M4BChapter> m4bChapters,
    Duration? totalDuration,
    Uint8List? coverArt,
  }) {
    return Audiobook(
      id: filePath,
      title: title,
      author: author,
      chapters: [], // Empty traditional chapters
      totalDuration: totalDuration ?? Duration.zero,
      coverArt: coverArt,
      isM4B: true,
      m4bChapters: m4bChapters,
      m4bFilePath: filePath,
    );
  }

  /// Copy method for updating audiobook properties
  Audiobook copyWith({
    String? id,
    String? title,
    String? author,
    List<Chapter>? chapters,
    Duration? totalDuration,
    Uint8List? coverArt,
    bool? isM4B,
    List<M4BChapter>? m4bChapters,
    String? m4bFilePath,
  }) {
    return Audiobook(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      chapters: chapters ?? this.chapters,
      totalDuration: totalDuration ?? this.totalDuration,
      coverArt: coverArt ?? this.coverArt,
      isM4B: isM4B ?? this.isM4B,
      m4bChapters: m4bChapters ?? this.m4bChapters,
      m4bFilePath: m4bFilePath ?? this.m4bFilePath,
    );
  }
}
