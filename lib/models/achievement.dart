import 'package:flutter/material.dart';

/// Represents a reading achievement/badge
class Achievement {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final AchievementTier tier;
  final AchievementCategory category;
  final int? targetValue; // e.g., 60 for "Read for 1 hour"
  final bool isSecret; // Hidden until unlocked
  final DateTime? unlockedAt;

  const Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.tier,
    required this.category,
    this.targetValue,
    this.isSecret = false,
    this.unlockedAt,
  });

  bool get isUnlocked => unlockedAt != null;

  /// Create unlocked version
  Achievement unlock() {
    return Achievement(
      id: id,
      name: name,
      description: description,
      icon: icon,
      tier: tier,
      category: category,
      targetValue: targetValue,
      isSecret: isSecret,
      unlockedAt: DateTime.now(),
    );
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'unlockedAt': unlockedAt?.millisecondsSinceEpoch,
    };
  }

  /// Create from stored unlock data
  static Achievement? fromStoredData(
    Map<String, dynamic> json,
    Map<String, Achievement> definitions,
  ) {
    final id = json['id'] as String;
    final definition = definitions[id];
    if (definition == null) return null;

    final unlockedAtMs = json['unlockedAt'] as int?;
    return Achievement(
      id: definition.id,
      name: definition.name,
      description: definition.description,
      icon: definition.icon,
      tier: definition.tier,
      category: definition.category,
      targetValue: definition.targetValue,
      isSecret: definition.isSecret,
      unlockedAt: unlockedAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(unlockedAtMs)
          : null,
    );
  }

  /// Get color based on tier
  Color get tierColor {
    switch (tier) {
      case AchievementTier.bronze:
        return const Color(0xFFCD7F32);
      case AchievementTier.silver:
        return const Color(0xFFC0C0C0);
      case AchievementTier.gold:
        return const Color(0xFFFFD700);
      case AchievementTier.platinum:
        return const Color(0xFFE5E4E2);
      case AchievementTier.diamond:
        return const Color(0xFFB9F2FF);
    }
  }
}

/// Achievement tier levels
enum AchievementTier {
  bronze,
  silver,
  gold,
  platinum,
  diamond,
}

/// Achievement categories
enum AchievementCategory {
  time, // Total listening time
  streak, // Consecutive days
  sessions, // Number of sessions
  books, // Books completed
  explorer, // Variety/exploration
  special, // Secret/special achievements
}

/// Extension for tier display names
extension AchievementTierExt on AchievementTier {
  String get displayName {
    switch (this) {
      case AchievementTier.bronze:
        return 'Bronze';
      case AchievementTier.silver:
        return 'Silver';
      case AchievementTier.gold:
        return 'Gold';
      case AchievementTier.platinum:
        return 'Platinum';
      case AchievementTier.diamond:
        return 'Diamond';
    }
  }
}

/// Extension for category display names
extension AchievementCategoryExt on AchievementCategory {
  String get displayName {
    switch (this) {
      case AchievementCategory.time:
        return 'Time Listener';
      case AchievementCategory.streak:
        return 'Streak Master';
      case AchievementCategory.sessions:
        return 'Session Pro';
      case AchievementCategory.books:
        return 'Book Worm';
      case AchievementCategory.explorer:
        return 'Explorer';
      case AchievementCategory.special:
        return 'Special';
    }
  }

  IconData get icon {
    switch (this) {
      case AchievementCategory.time:
        return Icons.timer;
      case AchievementCategory.streak:
        return Icons.local_fire_department;
      case AchievementCategory.sessions:
        return Icons.play_circle;
      case AchievementCategory.books:
        return Icons.menu_book;
      case AchievementCategory.explorer:
        return Icons.explore;
      case AchievementCategory.special:
        return Icons.star;
    }
  }
}
