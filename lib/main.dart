// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart' as provider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'providers/audiobook_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/library_screen.dart';
import 'screens/simple_player_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/license_check_screen.dart';


import 'services/audio_handler.dart';
import 'services/storage_service.dart';
import 'theme.dart';
import 'providers/sleep_timer_provider.dart';
import 'providers/tag_provider.dart';

// Global flag for audio service initialization
bool _audioServiceInitialized = false;
bool _isInitializing = false;

Future<void> main() async {
  debugPrint("===== main() started =====");

  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint("WidgetsFlutterBinding initialized.");

  // Enable all orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Initialize data integrity system
  await _initializeDataIntegrity();

  // Initialize audio background service
    await JustAudioBackground.init(
    androidNotificationChannelId: 'com.widdlereader.app.channel.audio',
      androidNotificationChannelName: 'Audiobook Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    notificationColor: Colors.deepPurple.shade900,
      androidShowNotificationBadge: true,
    preloadArtwork: true,
  );

  runApp(const ProviderScope(child: MyApp()));
}

// Initialize data integrity system
Future<void> _initializeDataIntegrity() async {
  try {
    debugPrint("Initializing data integrity system...");
    final storageService = StorageService();
    
    // Check data health and attempt recovery if needed
    final healthCheck = await storageService.checkDataHealth();
    debugPrint("Data health check results: $healthCheck");
    
    // Create a data backup on app start
    await storageService.createDataBackup();
    
    // Force persist any cached data from previous sessions
    await storageService.forcePersistCaches();
    
    debugPrint("Data integrity system initialized successfully");
  } catch (e) {
    debugPrint("Error initializing data integrity system: $e");
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final StorageService _storageService = StorageService();
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _storageService.dispose();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint("App lifecycle state changed to: $state");
    if (state == AppLifecycleState.paused) {
      // App is in background, persist cached data
      _storageService.forcePersistCaches();
    } else if (state == AppLifecycleState.resumed) {
      // App is in foreground again, check data health
      _storageService.checkDataHealth();
    } else if (state == AppLifecycleState.detached) {
      // App is terminated, ensure we clean up properly
      _storageService.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return provider.MultiProvider(
      providers: [
        provider.ChangeNotifierProvider(create: (_) => AudiobookProvider()),
        provider.ChangeNotifierProvider(create: (_) => ThemeProvider()),
        provider.ChangeNotifierProvider(create: (_) => SleepTimerProvider()),
      ],
      child: provider.Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Widdle Reader',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme(themeProvider.seedColor),
            darkTheme: AppTheme.darkTheme(themeProvider.seedColor),
            themeMode: themeProvider.themeMode,
            initialRoute: '/license',
            routes: {
              '/license': (context) => const LicenseCheckScreen(),
              '/splash': (context) => const SplashScreen(),
              '/library': (context) => const LibraryScreen(),
              '/player': (context) => const SimplePlayerScreen(),
              '/settings': (context) => const SettingsScreen(),
              // BookmarksScreen is not registered here since it requires parameters
              // and is opened using Navigator.push with MaterialPageRoute
            },
          );
        },
      ),
    );
  }
}
