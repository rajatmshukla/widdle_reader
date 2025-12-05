import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math';
import '../services/statistics_service.dart';

/// Weekly challenge service for generating and tracking challenges
class ChallengeService {
  static final ChallengeService _instance = ChallengeService._internal();
  factory ChallengeService() => _instance;
  ChallengeService._internal();

  static const String activeChallengesKey = 'active_challenges';
  static const String completedChallengesKey = 'completed_challenges';

  SharedPreferences? _prefs;
  final StatisticsService _statsService = StatisticsService();

  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// Get active challenges, generating new ones if needed
  Future<List<Challenge>> getActiveChallenges() async {
    final prefs = await _preferences;
    final jsonString = prefs.getString(activeChallengesKey);

    if (jsonString != null) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        final challenges = jsonList
            .map((json) => Challenge.fromJson(json))
            .where((c) => !c.isExpired)
            .toList();

        if (challenges.isNotEmpty) {
          return challenges;
        }
      } catch (e) {
        debugPrint('Error loading challenges: $e');
      }
    }

    // Generate new challenges
    return await _generateWeeklyChallenges();
  }

  /// Generate new weekly challenges
  Future<List<Challenge>> _generateWeeklyChallenges() async {
    final now = DateTime.now();
    final weekEnd = now.add(Duration(days: 7 - now.weekday));
    final endOfWeek = DateTime(weekEnd.year, weekEnd.month, weekEnd.day, 23, 59, 59);

    // Get current stats for baseline
    final streak = await _statsService.getStreak();
    final avgSession = await _statsService.getAverageSessionDuration();

    final challenges = <Challenge>[
      // Time challenge
      Challenge(
        id: 'weekly_time_${now.millisecondsSinceEpoch}',
        type: ChallengeType.totalTime,
        title: 'Weekly Listener',
        description: 'Listen for 3 hours this week',
        targetValue: 180, // 3 hours in minutes
        currentValue: 0,
        xpReward: 50,
        expiresAt: endOfWeek,
      ),
      // Session challenge
      Challenge(
        id: 'weekly_sessions_${now.millisecondsSinceEpoch}',
        type: ChallengeType.sessions,
        title: 'Session Pro',
        description: 'Complete 10 reading sessions',
        targetValue: 10,
        currentValue: 0,
        xpReward: 30,
        expiresAt: endOfWeek,
      ),
      // Streak challenge
      Challenge(
        id: 'weekly_streak_${now.millisecondsSinceEpoch}',
        type: ChallengeType.streak,
        title: 'Keep the Flame',
        description: 'Maintain a 5-day streak',
        targetValue: 5,
        currentValue: streak.currentStreak,
        xpReward: 40,
        expiresAt: endOfWeek,
      ),
    ];

    // Save new challenges
    await _saveChallenges(challenges);
    return challenges;
  }

  /// Update challenge progress
  Future<List<Challenge>> updateChallengeProgress() async {
    final challenges = await getActiveChallenges();
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));

    // Get current week stats
    final minutesThisWeek = await _statsService.getTotalMinutesThisWeek();
    final sessionsThisWeek = await _statsService.getTotalSessionsThisWeek();
    final streak = await _statsService.getStreak();

    for (final challenge in challenges) {
      switch (challenge.type) {
        case ChallengeType.totalTime:
          challenge.currentValue = minutesThisWeek;
          break;
        case ChallengeType.sessions:
          challenge.currentValue = sessionsThisWeek;
          break;
        case ChallengeType.streak:
          challenge.currentValue = streak.currentStreak;
          break;
        case ChallengeType.daily:
          // Not implemented yet
          break;
      }
    }

    await _saveChallenges(challenges);
    return challenges;
  }

  /// Save challenges to storage
  Future<void> _saveChallenges(List<Challenge> challenges) async {
    final prefs = await _preferences;
    final jsonList = challenges.map((c) => c.toJson()).toList();
    await prefs.setString(activeChallengesKey, jsonEncode(jsonList));
  }

  /// Get completed challenges count
  Future<int> getCompletedCount() async {
    final prefs = await _preferences;
    return prefs.getInt(completedChallengesKey) ?? 0;
  }

  /// Mark challenge as completed
  Future<void> markCompleted(String challengeId) async {
    final prefs = await _preferences;
    final count = await getCompletedCount();
    await prefs.setInt(completedChallengesKey, count + 1);
  }
}

/// Challenge model
class Challenge {
  final String id;
  final ChallengeType type;
  final String title;
  final String description;
  final int targetValue;
  int currentValue;
  final int xpReward;
  final DateTime expiresAt;

  Challenge({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.targetValue,
    required this.currentValue,
    required this.xpReward,
    required this.expiresAt,
  });

  double get progress => (currentValue / targetValue).clamp(0.0, 1.0);
  bool get isComplete => currentValue >= targetValue;
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.index,
        'title': title,
        'description': description,
        'targetValue': targetValue,
        'currentValue': currentValue,
        'xpReward': xpReward,
        'expiresAt': expiresAt.millisecondsSinceEpoch,
      };

  factory Challenge.fromJson(Map<String, dynamic> json) => Challenge(
        id: json['id'],
        type: ChallengeType.values[json['type']],
        title: json['title'],
        description: json['description'],
        targetValue: json['targetValue'],
        currentValue: json['currentValue'],
        xpReward: json['xpReward'],
        expiresAt: DateTime.fromMillisecondsSinceEpoch(json['expiresAt']),
      );
}

/// Challenge types
enum ChallengeType {
  totalTime,
  sessions,
  streak,
  daily,
}

extension ChallengeTypeExt on ChallengeType {
  IconData get icon {
    switch (this) {
      case ChallengeType.totalTime:
        return Icons.timer;
      case ChallengeType.sessions:
        return Icons.play_circle;
      case ChallengeType.streak:
        return Icons.local_fire_department;
      case ChallengeType.daily:
        return Icons.today;
    }
  }

  Color get color {
    switch (this) {
      case ChallengeType.totalTime:
        return Colors.blue;
      case ChallengeType.sessions:
        return Colors.green;
      case ChallengeType.streak:
        return Colors.orange;
      case ChallengeType.daily:
        return Colors.purple;
    }
  }
}
