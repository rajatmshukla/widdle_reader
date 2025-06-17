class Tag {
  final String name;           // Unique tag identifier
  final DateTime createdAt;    // Creation timestamp
  final DateTime lastUsedAt;   // Last usage for sorting
  final int bookCount;         // Number of books with this tag
  final bool isFavorites;      // Special "Favorites" tag flag

  const Tag({
    required this.name,
    required this.createdAt,
    required this.lastUsedAt,
    required this.bookCount,
    this.isFavorites = false,
  });

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      name: json['name'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUsedAt: DateTime.parse(json['lastUsedAt'] as String),
      bookCount: json['bookCount'] as int,
      isFavorites: json['isFavorites'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'lastUsedAt': lastUsedAt.toIso8601String(),
      'bookCount': bookCount,
      'isFavorites': isFavorites,
    };
  }

  Tag copyWith({
    String? name,
    DateTime? createdAt,
    DateTime? lastUsedAt,
    int? bookCount,
    bool? isFavorites,
  }) {
    return Tag(
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      bookCount: bookCount ?? this.bookCount,
      isFavorites: isFavorites ?? this.isFavorites,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Tag && other.name == name;
  }

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return 'Tag(name: $name, bookCount: $bookCount, isFavorites: $isFavorites)';
  }
}

enum TagSortOption {
  alphabeticalAZ,
  alphabeticalZA,
  recentlyUsed,
  recentlyCreated,
}

extension TagSortOptionExtension on TagSortOption {
  String get displayName {
    switch (this) {
      case TagSortOption.alphabeticalAZ:
        return 'A-Z';
      case TagSortOption.alphabeticalZA:
        return 'Z-A';
      case TagSortOption.recentlyUsed:
        return 'Recently Used';
      case TagSortOption.recentlyCreated:
        return 'Recently Created';
    }
  }
} 