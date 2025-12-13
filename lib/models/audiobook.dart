import 'dart:typed_data';
import 'chapter.dart';

class Audiobook {
  final String id; // Use folder path as unique ID
  final String title;
  final String? author; // Add author field
  final List<Chapter> chapters;
  Duration totalDuration;
  double? rating;        // 1-5 star rating
  String? review;        // Rich text review content (JSON Delta)
  DateTime? reviewTimestamp; // When the review was last updated
  Uint8List? coverArt; // Store cover art data
  Set<String> tags;      // Multiple tags per book
  bool isFavorited;      // Quick favorites access

  Audiobook({
    required this.id,
    required this.title,
    this.author, // Add author parameter to constructor
    required this.chapters,
    this.totalDuration = Duration.zero,
    this.coverArt,
    Set<String>? tags,
    this.isFavorited = false,
    this.rating,
    this.review,
    this.reviewTimestamp,
  }) : tags = tags ?? <String>{};

  // Methods for tag management
  bool hasTag(String tagName) {
    return tags.contains(tagName);
  }

  void addTag(String tagName) {
    tags.add(tagName);
    if (tagName.toLowerCase() == 'favorites') {
      isFavorited = true;
    }
  }

  void removeTag(String tagName) {
    tags.remove(tagName);
    if (tagName.toLowerCase() == 'favorites') {
      isFavorited = false;
    }
  }

  void toggleFavorite() {
    isFavorited = !isFavorited;
    if (isFavorited) {
      tags.add('Favorites');
    } else {
      tags.remove('Favorites');
    }
  }

  // Serialization methods
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'totalDuration': totalDuration.inMilliseconds,
      'tags': tags.toList(),
      'isFavorited': isFavorited,
      'rating': rating,
      'review': review,
      'reviewTimestamp': reviewTimestamp?.toIso8601String(),
    };
  }

  factory Audiobook.fromJson(Map<String, dynamic> json) {
    return Audiobook(
      id: json['id'] as String,
      title: json['title'] as String,
      author: json['author'] as String?,
      chapters: [], // Would need to be handled separately
      totalDuration: Duration(milliseconds: json['totalDuration'] as int? ?? 0),
      tags: Set<String>.from(json['tags'] as List? ?? []),
      isFavorited: json['isFavorited'] as bool? ?? false,
      rating: json['rating'] != null ? (json['rating'] as num).toDouble() : null,
      review: json['review'] as String?,
      reviewTimestamp: json['reviewTimestamp'] != null 
          ? DateTime.tryParse(json['reviewTimestamp'] as String) 
          : null,
    );
  }

  Audiobook copyWith({
    String? id,
    String? title,
    String? author,
    List<Chapter>? chapters,
    Duration? totalDuration,
    Uint8List? coverArt,
    Set<String>? tags,
    bool? isFavorited,
    double? rating,
    String? review,
    DateTime? reviewTimestamp,
  }) {
    return Audiobook(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      chapters: chapters ?? this.chapters,
      totalDuration: totalDuration ?? this.totalDuration,
      coverArt: coverArt ?? this.coverArt,
      tags: tags ?? Set<String>.from(this.tags),
      isFavorited: isFavorited ?? this.isFavorited,
      rating: rating ?? this.rating,
      review: review ?? this.review,
      reviewTimestamp: reviewTimestamp ?? this.reviewTimestamp,
    );
  }
}
