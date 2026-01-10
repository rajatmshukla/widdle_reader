import 'package:flutter/material.dart';

/// Represents a highlight or annotation in an eBook.
class ReaderAnnotation {
  final String id;
  final String ebookId;
  final String? cfi; // EPUB location
  final int? pageNumber; // PDF page
  final String selectedText;
  final String? note;
  final int colorHex;
  final DateTime createdAt;

  ReaderAnnotation({
    required this.id,
    required this.ebookId,
    this.cfi,
    this.pageNumber,
    required this.selectedText,
    this.note,
    this.colorHex = 0xFFFFEB3B, // Yellow default
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Color get color => Color(colorHex);

  factory ReaderAnnotation.create({
    required String ebookId,
    String? cfi,
    int? pageNumber,
    required String selectedText,
    String? note,
    int colorHex = 0xFFFFEB3B,
  }) {
    final now = DateTime.now();
    return ReaderAnnotation(
      id: '$ebookId-${now.millisecondsSinceEpoch}',
      ebookId: ebookId,
      cfi: cfi,
      pageNumber: pageNumber,
      selectedText: selectedText,
      note: note,
      colorHex: colorHex,
      createdAt: now,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ebookId': ebookId,
      'cfi': cfi,
      'pageNumber': pageNumber,
      'selectedText': selectedText,
      'note': note,
      'colorHex': colorHex,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ReaderAnnotation.fromJson(Map<String, dynamic> json) {
    return ReaderAnnotation(
      id: (json['id'] ?? 'unknown-${DateTime.now().millisecondsSinceEpoch}').toString(),
      ebookId: (json['ebookId'] ?? 'unknown').toString(),
      cfi: json['cfi']?.toString(),
      pageNumber: json['pageNumber'] as int?,
      selectedText: (json['selectedText'] ?? '').toString(),
      note: json['note']?.toString(),
      colorHex: json['colorHex'] as int? ?? 0xFFFFEB3B,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  ReaderAnnotation copyWith({
    String? id,
    String? ebookId,
    String? cfi,
    int? pageNumber,
    String? selectedText,
    String? note,
    int? colorHex,
    DateTime? createdAt,
  }) {
    return ReaderAnnotation(
      id: id ?? this.id,
      ebookId: ebookId ?? this.ebookId,
      cfi: cfi ?? this.cfi,
      pageNumber: pageNumber ?? this.pageNumber,
      selectedText: selectedText ?? this.selectedText,
      note: note ?? this.note,
      colorHex: colorHex ?? this.colorHex,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// Preset highlight colors for the reader.
class HighlightColors {
  static const int yellow = 0xFFFFEB3B;
  static const int green = 0xFF4CAF50;
  static const int blue = 0xFF2196F3;
  static const int pink = 0xFFE91E63;
  static const int orange = 0xFFFF9800;

  static const List<int> all = [yellow, green, blue, pink, orange];
}
