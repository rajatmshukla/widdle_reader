// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode
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


import 'services/storage_service.dart';
import 'services/simple_audio_service.dart';
import 'services/android_auto_manager.dart';
import 'theme.dart';
import 'providers/sleep_timer_provider.dart';
import 'providers/tag_provider.dart';

// CRITICAL FIX: Add release-safe logging for main
void _logDebug(String message) {
  if (kDebugMode) {
    debugPrint(message);
  } else {
    print("[Main] $message");
  }
}

// Global flag for audio service initialization
bool _audioServiceInitialized = false;
bool _isInitializing = false;

Future<void> main() async {
  _logDebug("===== main() started =====");

  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();
  _logDebug("WidgetsFlutterBinding initialized.");

  // Enable all orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Initialize data integrity system
  await _initializeDataIntegrity();
  
  // Initialize Android Auto support (will only activate on Android)
  await _initializeAndroidAuto();

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
    _logDebug("Initializing data integrity system...");
    final storageService = StorageService();
    
    // Check data health and attempt recovery if needed
    final healthCheck = await storageService.checkDataHealth();
    _logDebug("Data health check results: $healthCheck");
    
    // Create a data backup on app start
    await storageService.createDataBackup();
    
    // Force persist any cached data from previous sessions
    await storageService.forcePersistCaches();
    
    _logDebug("Data integrity system initialized successfully");
  } catch (e) {
    _logDebug("Error initializing data integrity system: $e");
  }
}

// Initialize Android Auto integration
Future<void> _initializeAndroidAuto() async {
  try {
    _logDebug("Initializing Android Auto support...");
    
    // Android Auto manager will check platform and only initialize on Android
    final androidAutoManager = AndroidAutoManager();
    
    // Note: Full initialization happens after providers are available
    // This is just a pre-initialization to set up the service
    
    _logDebug("Android Auto support prepared successfully");
  } catch (e) {
    _logDebug("Error initializing Android Auto: $e (this is normal on non-Android platforms)");
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final StorageService _storageService = StorageService();
  final SimpleAudioService _audioService = SimpleAudioService();
  bool _androidAutoInitialized = false;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize audio service
    _audioService.init();
    
    // Initialize Android Auto after build to ensure providers are ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeAndroidAutoFully();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _storageService.dispose();
    
    // Dispose Android Auto manager
    if (_androidAutoInitialized) {
      AndroidAutoManager().dispose();
    }
    
    super.dispose();
  }
  
  /// Full initialization of Android Auto with provider access
  /// NOTE: This runs BEFORE providers are mounted, so it will fail
  /// The actual initialization happens in LibraryScreen where providers are available
  Future<void> _initializeAndroidAutoFully() async {
    if (_androidAutoInitialized || !mounted) return;
    
    try {
      _logDebug("🔧 Early Android Auto init skipped - waiting for LibraryScreen");
      _logDebug("📌 Providers are not yet available at this level");
      
      // Don't try to initialize here - let LibraryScreen do it
      // where providers are guaranteed to be available
      _androidAutoInitialized = true;
    } catch (e) {
      _logDebug("❌ Error in early Android Auto check: $e");
    }
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _logDebug("App lifecycle state changed to: $state");
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
