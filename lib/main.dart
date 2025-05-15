// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';

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

  try {
    // First initialize just_audio_background which handles media notifications
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.example.widdle_reader.channel.audio',
      androidNotificationChannelName: 'Audiobook Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidShowNotificationBadge: true,
      fastForwardInterval: const Duration(seconds: 30),
      rewindInterval: const Duration(seconds: 30),
      androidNotificationIcon: 'mipmap/ic_launcher',
      androidNotificationClickStartsActivity: true,
      notificationColor: const Color(0xFF2196f3),
    );
    
    debugPrint("JustAudioBackground initialized successfully.");
    
    // We'll initialize the audio handler when it's actually needed
    // instead of at app startup to avoid initialization issues
  } catch (e, stackTrace) {
    debugPrint("Error initializing audio services: $e");
    debugPrint("$stackTrace");
  }

  runApp(const MyApp());
  debugPrint("===== main() finished (runApp called) =====");
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
