// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

import 'providers/audiobook_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/library_screen.dart';
import 'screens/simple_player_screen.dart';
import 'screens/settings_screen.dart';

import 'services/audio_handler.dart';
import 'theme.dart';

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

  // Try to initialize audio service, but don't block app launch if it fails
  try {
    await initializeAudioService();
  } catch (e, stackTrace) {
    debugPrint("Error initializing audio service in main: $e");
    debugPrint("$stackTrace");
  }

  runApp(const MyApp());
  debugPrint("===== main() finished (runApp called) =====");
}

// Safe initialization function with checks to prevent multiple initializations
Future<bool> initializeAudioService() async {
  // If already initialized, return true
  if (_audioServiceInitialized) {
    debugPrint("Audio service already initialized.");
    return true;
  }

  // If currently initializing, wait and return the result
  if (_isInitializing) {
    debugPrint("Audio service initialization already in progress. Waiting...");
    // Wait for up to 5 seconds for initialization to complete
    for (int i = 0; i < 50; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (_audioServiceInitialized) {
        return true;
      }
    }
    throw Exception("Timeout waiting for audio service initialization");
  }

  // Start initialization
  _isInitializing = true;
  try {
    debugPrint("Starting audio service initialization...");
    await initAudioService();
    _audioServiceInitialized = true;
    debugPrint("Audio service initialized successfully!");
    return true;
  } catch (e) {
    debugPrint("Failed to initialize audio service: $e");
    _isInitializing = false;
    rethrow;
  } finally {
    _isInitializing = false;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AudiobookProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Widdle Reader',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme(themeProvider.seedColor),
            darkTheme: AppTheme.darkTheme(themeProvider.seedColor),
            themeMode: themeProvider.themeMode,
            initialRoute: '/splash',
            routes: {
              '/splash': (context) => const SplashScreen(),
              '/library': (context) => const LibraryScreen(),
              '/player': (context) => const SimplePlayerScreen(),
              '/settings': (context) => const SettingsScreen(),
            },
          );
        },
      ),
    );
  }
}
