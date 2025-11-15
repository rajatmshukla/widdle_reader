import 'package:flutter/foundation.dart';

class Bookmark {
  final String id;          // Unique ID for the bookmark
  final String audiobookId; // ID of the audiobook
  final String chapterId;   // ID of the chapter
  final Duration position;  // Position within the chapter
  final String name;        // User-defined name for the bookmark
  final int timestamp;      // Creation timestamp

  Bookmark({
    required this.id,
    required this.audiobookId,
    required this.chapterId,
    required this.position,
    required this.name,
    required this.timestamp,
  });

  // Create a bookmark with a generated ID
  factory Bookmark.create({
    required String audiobookId,
    required String chapterId,
    required Duration position,
    required String name,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = '$audiobookId-$chapterId-$now';
    
    return Bookmark(
      id: id,
      audiobookId: audiobookId,
      chapterId: chapterId,
      position: position,
      name: name,
      timestamp: now,
    );
  }

  // Convert to a map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'audiobookId': audiobookId,
      'chapterId': chapterId,
      'position': position.inMilliseconds,
      'name': name,
      'timestamp': timestamp,
    };
  }

  // Create from a storage map
  factory Bookmark.fromMap(Map<String, dynamic> map) {
    return Bookmark(
      id: map['id'],
      audiobookId: map['audiobookId'],
      chapterId: map['chapterId'],
      position: Duration(milliseconds: map['position']),
      name: map['name'],
      timestamp: map['timestamp'],
    );
  }

  // Create a copy with updated fields
  Bookmark copyWith({
    String? id,
    String? audiobookId,
    String? chapterId,
    Duration? position,
    String? name,
    int? timestamp,
  }) {
    return Bookmark(
      id: id ?? this.id,
      audiobookId: audiobookId ?? this.audiobookId,
      chapterId: chapterId ?? this.chapterId,
      position: position ?? this.position,
      name: name ?? this.name,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Bookmark && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
} 