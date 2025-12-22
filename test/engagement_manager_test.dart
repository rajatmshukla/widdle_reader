import 'package:flutter_test/flutter_test.dart';
import 'package:widdle_reader/services/engagement_manager.dart';
import 'package:widdle_reader/services/notification_service.dart';
import 'package:widdle_reader/services/statistics_service.dart';
import 'package:widdle_reader/services/personality_service.dart';
import 'package:widdle_reader/models/reading_statistics.dart';
import 'package:widdle_reader/models/achievement.dart'; // For Achievement definitions if needed

// Manual Fake for NotificationService
class FakeNotificationService implements NotificationService {
  int scheduledId = -1;
  String scheduledTitle = '';
  String scheduledBody = '';
  DateTime? scheduledDate;

  bool initialized = false;

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    scheduledId = id;
    scheduledTitle = title;
    scheduledBody = body;
    this.scheduledDate = scheduledDate;
  }

  @override
  Future<void> showAchievementNotification(Achievement achievement) async {}

  @override
  Future<void> cancelAll() async {}
}

// Manual Fake for StatisticsService
class FakeStatisticsService implements StatisticsService {
  ReadingStreak _streak = ReadingStreak.empty();
  
  void setStreak(ReadingStreak streak) {
    _streak = streak;
  }

  @override
  Future<ReadingStreak> getStreak() async => _streak;

  // Stubs for other methods to satisfy interface
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Manual Fake for PersonalityService
class FakePersonalityService implements PersonalityService {
  ReadingPersonality _personality = ReadingPersonality.empty();

  void setPersonality(ReadingPersonality personality) {
    _personality = personality;
  }

  @override
  Future<ReadingPersonality> analyzePersonality() async => _personality;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late EngagementManager manager;
  late FakeNotificationService fakeNotificationService;
  late FakeStatisticsService fakeStatsService;
  late FakePersonalityService fakePersonalityService;

  setUp(() {
    fakeNotificationService = FakeNotificationService();
    fakeStatsService = FakeStatisticsService();
    fakePersonalityService = FakePersonalityService();

    manager = EngagementManager(
      notificationService: fakeNotificationService,
      statsService: fakeStatsService,
      personalityService: fakePersonalityService,
    );
  });

  group('EngagementManager Tests', () {
    test('Personalized Time - Night Owl gets 21:00', () async {
      fakePersonalityService.setPersonality(const ReadingPersonality(
        type: PersonalityType.scholar,
        timePreference: TimePreference.nightOwl, 
        sessionPattern: SessionPattern.casual,
        consistencyScore: 0,
        avgSessionMinutes: 0,
        currentStreak: 0,
        totalSessions: 0,
      ));

      await manager.initialize();
      
      final scheduledHour = fakeNotificationService.scheduledDate?.hour;
      expect(scheduledHour, 21);
    });

    test('Personalized Time - Early Bird gets shifted to 9:00 (due to Quiet Hours)', () async {
      fakePersonalityService.setPersonality(const ReadingPersonality(
        type: PersonalityType.sunriseReader,
        timePreference: TimePreference.earlyBird, 
        sessionPattern: SessionPattern.casual,
        consistencyScore: 0,
        avgSessionMinutes: 0,
        currentStreak: 0,
        totalSessions: 0,
      ));

      await manager.initialize();

      final scheduledHour = fakeNotificationService.scheduledDate?.hour;
      expect(scheduledHour, 9); 
    });

    test('Quiet Hours Shift - 7 AM becomes 9 AM', () async {
       fakePersonalityService.setPersonality(const ReadingPersonality(
        type: PersonalityType.sunriseReader,
        timePreference: TimePreference.earlyBird, // Base 07:00
        sessionPattern: SessionPattern.casual,
        consistencyScore: 0,
        avgSessionMinutes: 0,
        currentStreak: 0,
        totalSessions: 0,
      ));

      await manager.initialize();

      expect(fakeNotificationService.scheduledDate?.hour, 9);
    });

    test('Streak Notification has fun title', () async {
      fakeStatsService.setStreak(ReadingStreak(
        currentStreak: 5,
        longestStreak: 5,
        lastReadDate: DateTime.now().subtract(const Duration(days: 1)), // Read yesterday
      ));

      await manager.initialize();

      expect(fakeNotificationService.scheduledTitle, isNotEmpty);
      // We expect a fun message
      // "Fire", "Rocket", "Book", "Chain" etc.
      // Let's just check it's NOT the default "Time to Read?"
      expect(fakeNotificationService.scheduledTitle, isNot("📖 Time to Read?"));
      expect(fakeNotificationService.scheduledBody, contains("5")); // Should contain streak count
    });

    test('Engagement Notification uses simple title if no streak', () async {
      fakeStatsService.setStreak(ReadingStreak.empty());

      await manager.initialize();

      expect(fakeNotificationService.scheduledTitle, "📖 Time to Read?");
    });
  });
}
