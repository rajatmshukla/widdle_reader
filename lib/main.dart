import 'dart:async'; // For runZonedGuarded
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode
import 'package:provider/provider.dart' as provider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart'; // For FlutterQuillLocalizations
import 'package:just_audio_background/just_audio_background.dart';

import 'providers/audiobook_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/sleep_timer_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/library_screen.dart';
import 'screens/simple_player_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/license_check_screen.dart';
import 'screens/holiday_splash_screen.dart';
import 'screens/statistics_screen.dart';
import 'theme.dart';
import 'services/storage_service.dart';
import 'services/simple_audio_service.dart';
import 'services/statistics_service.dart';
import 'services/achievement_service.dart';
import 'services/notification_service.dart';
import 'services/widget_service.dart';
import 'services/pulse_sync_service.dart';
import 'widgets/snow_overlay.dart'; // Import global snow overlay

// Define a global navigator key to access context from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// CRITICAL FIX: Add release-safe logging for main
void _logDebug(String message) {
  if (kDebugMode) {
    debugPrint(message);
  } else {
    // In release mode, we might want to log critical events to a file or analytics
    // For now, just suppress to avoid performance impact
    // print("[Main] $message"); // Uncomment if console logs are needed in release
  }
}

void main() {
  // Wrap the entire app in a zone to catch unhandled errors
  runZonedGuarded(() async {
    _logDebug("===== main() started =====");

    WidgetsFlutterBinding.ensureInitialized();
    
    // Enable all orientations
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (e) {
      _logDebug("Error setting orientations: $e");
    }

    // Initialize data integrity system (Safe-guarded internally)
    await _initializeDataIntegrity();

    // Initialize JustAudioBackground with safety check
    try {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.ryanheise.bg_demo.channel.audio',
        androidNotificationChannelName: 'Audio playback',
        androidNotificationOngoing: true,
        // Enable standard media controls
        fastForwardInterval: const Duration(seconds: 15),
        rewindInterval: const Duration(seconds: 15),
      );
      _logDebug("JustAudioBackground initialized successfully");
    } catch (e) {
      _logDebug("CRITICAL ERROR: Failed to initialize JustAudioBackground: $e");
      // We continue anyway - the app should open even if background audio fails
    }

    runApp(
      ProviderScope(
        child: provider.MultiProvider(
          providers: [
            provider.ChangeNotifierProvider(create: (_) => AudiobookProvider()),
            provider.ChangeNotifierProvider(create: (_) => ThemeProvider()),
            provider.ChangeNotifierProvider(create: (_) => SleepTimerProvider()),
          ],
          child: const MyApp(),
        ),
      ),
    );
  }, (error, stack) {
    // Global error handler
    _logDebug("UNCAUGHT ERROR IN MAIN ZONE: $error");
    _logDebug("Stack trace: $stack");
    // In a real production app, report this to Crashlytics/Sentry
  });
}

// Initialize data integrity system
Future<void> _initializeDataIntegrity() async {
  try {
    _logDebug("Initializing data integrity system...");
    final storageService = StorageService();
    
    // Initialize notification service
    await NotificationService().initialize();
    _logDebug("Notification service initialized");
    
    // Check data health and attempt recovery if needed
    final healthCheck = await storageService.checkDataHealth();
    _logDebug("Data health check results: $healthCheck");
    
    // Create a data backup on app start
    await storageService.createDataBackup();
    
    // Force persist any cached data from previous sessions
    await storageService.forcePersistCaches();
    
    // Initialize statistics service and recover any crashed sessions
    final statisticsService = StatisticsService();
    await statisticsService.initialize();
    _logDebug("Statistics service initialized with session recovery");
    
    // Initialize achievement service for gamification
    final achievementService = AchievementService();
    await achievementService.initialize();
    _logDebug("Achievement service initialized");
    
    // Initialize home screen widget service
    final widgetService = WidgetService();
    await widgetService.initialize();
    _logDebug("Widget service initialized");
    
    // Initialize Pulse Sync Service for cross-device sync
    final pulseSyncService = PulseSyncService();
    await pulseSyncService.initialize();
    // Initial sync on startup
    await pulseSyncService.pulseIn();
    _logDebug("Pulse Sync Service initialized and initial sync complete");
    
    _logDebug("Data integrity system initialized successfully");
  } catch (e) {
    _logDebug("Error initializing data integrity system: $e");
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();

  /// Check if current date is within holiday season (Dec 23 - Jan 4)
  static bool isHolidaySeason() {
    final now = DateTime.now();
    final month = now.month;
    final day = now.day;
    
    // December 23-31
    if (month == 12 && day >= 23) return true;
    // January 1-4
    if (month == 1 && day <= 4) return true;
    
    return false;
  }
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final StorageService _storageService = StorageService();
  final SimpleAudioService _audioService = SimpleAudioService();
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize audio service
    _audioService.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // We don't dispose storage service here as it's a singleton used elsewhere
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _logDebug("App lifecycle state changed to: $state");
    if (state == AppLifecycleState.paused) {
      // App is in background, persist cached data and sync out
      _storageService.forcePersistCaches();
      PulseSyncService().pulseOut();
    } else if (state == AppLifecycleState.resumed) {
      // App is in foreground again, check data health and sync in
      _storageService.checkDataHealth();
      PulseSyncService().pulseIn();
    } else if (state == AppLifecycleState.detached) {
      // App is terminated, ensure we clean up properly
      _storageService.forcePersistCaches();
      PulseSyncService().pulseOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return provider.Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'Widdle Reader',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme(themeProvider.seedColor),
          darkTheme: AppTheme.darkTheme(themeProvider.seedColor),
          themeMode: themeProvider.themeMode,
          
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: FlutterQuillLocalizations.supportedLocales,
          
          // Show holiday splash during Dec 23 - Jan 4, otherwise go to license check
          home: MyApp.isHolidaySeason()
              ? HolidaySplashScreen(
                  onComplete: () {
                    navigatorKey.currentState?.pushNamedAndRemoveUntil(
                      '/license',
                      (route) => false,
                    );
                  },
                )
              : const LicenseCheckScreen(),
          routes: {
            '/license': (context) => const LicenseCheckScreen(),
            '/splash': (context) => const SplashScreen(),
            '/library': (context) => const LibraryScreen(),
            '/player': (context) => const SimplePlayerScreen(),
            '/settings': (context) => const SettingsScreen(),
            '/statistics': (context) => const StatisticsScreen(),
          },

          // Global builder for overlays (Snow Effect)
          builder: (context, child) {
            return Stack(
              children: [
                if (child != null) child,
                const SnowOverlay(),
              ],
            );
          },
        );
      },
    );
  }
}
