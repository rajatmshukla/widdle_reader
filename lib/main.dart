import 'package:flutter/material.dart'; // Import Material widgets
import 'package:provider/provider.dart'; // Import Provider for state management

// Import local providers, screens, and services
import 'providers/audiobook_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/library_screen.dart';
import 'screens/player_screen.dart';
import 'services/audio_handler.dart'; // *** Import initAudioService and the handler itself ***

/// The main entry point of the application.
Future<void> main() async {
  // --- Start of Diagnostic Logging ---
  debugPrint("===== main() started =====");

  // Ensure Flutter bindings are initialized before calling any platform-specific code.
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint("WidgetsFlutterBinding initialized.");

  // --- Initialize Audio Service ---
  // This step is critical and must complete successfully *before* runApp.
  try {
    debugPrint("Calling initAudioService()...");
    // Use 'await' to ensure initialization finishes before proceeding.
    await initAudioService();
    // *** Confirmation log if initialization succeeds ***
    debugPrint(">>> initAudioService() COMPLETED SUCCESSFULLY in main. <<<");
  } catch (e, stackTrace) {
    // *** Log details if initialization fails ***
    // The app WILL continue running after this, but audio handler will be null.
    debugPrint("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
    debugPrint(">>> FAILED TO INITIALIZE AUDIO SERVICE IN MAIN: $e <<<");
    debugPrint("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
    debugPrint("$stackTrace");
    debugPrint(
      ">>> Proceeding to run app despite audio service init failure. <<<",
    );
  }

  debugPrint("Proceeding to runApp()...");
  // Run the main Flutter application widget regardless of audio service init success/failure.
  runApp(const MyApp());
  debugPrint("===== main() finished (runApp called) =====");
  // --- End of Diagnostic Logging ---
}

/// The root widget of the application. Sets up providers and routing.
class MyApp extends StatelessWidget {
  // Use const constructor for stateless widgets.
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Use ChangeNotifierProvider to make AudiobookProvider available down the widget tree.
    return ChangeNotifierProvider(
      create: (context) => AudiobookProvider(), // Create the provider instance.
      child: MaterialApp(
        title: 'Audiobook Player', // Application title
        // Define the application's dark theme.
        theme: ThemeData(
          brightness: Brightness.dark,
          primarySwatch: Colors.teal, // Base color for the theme
          scaffoldBackgroundColor:
              Colors.grey[900], // Dark background for screens
          appBarTheme: AppBarTheme(
            // Style for AppBars
            backgroundColor: Colors.grey[850],
            elevation: 1,
            titleTextStyle: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w500,
            ),
            iconTheme: const IconThemeData(
              color: Colors.white,
            ), // AppBar icon color
          ),
          cardTheme: CardTheme(
            // Style for Cards
            color: Colors.grey[850],
            elevation: 0, // Flat card design
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            // Style for FAB
            backgroundColor: Colors.tealAccent,
            foregroundColor: Colors.black, // Icon color on FAB
          ),
          listTileTheme: ListTileThemeData(
            // Default style for ListTiles
            iconColor: Colors.grey[400],
            textColor: Colors.white,
          ),
          iconTheme: IconThemeData(
            color: Colors.tealAccent[100],
          ), // Default icon color
          sliderTheme: SliderThemeData(
            // Style for Seekbar/Sliders
            trackHeight: 3.0,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.0),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 15.0),
            activeTrackColor: Colors.tealAccent[100],
            inactiveTrackColor: Colors.grey[700],
            thumbColor: Colors.tealAccent,
            overlayColor: Colors.tealAccent.withAlpha(
              (255 * 0.2).round(),
            ), // Use withAlpha for opacity
            activeTickMarkColor: Colors.transparent,
            inactiveTickMarkColor: Colors.transparent,
          ),
          textTheme: const TextTheme(
            // Define text styles
            titleLarge: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w500,
            ),
            titleMedium: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            bodyMedium: TextStyle(color: Colors.white70, fontSize: 14),
            bodySmall: TextStyle(color: Colors.grey, fontSize: 12),
            labelLarge: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ).apply(
            // Apply default text colors if needed
            bodyColor: Colors.white,
            displayColor: Colors.white,
          ),
          colorScheme: ColorScheme.fromSwatch(
            // Define color scheme
            brightness: Brightness.dark,
            primarySwatch: Colors.teal,
          ).copyWith(
            primary: Colors.tealAccent[100], // Highlight/active color
            secondary: Colors.tealAccent, // Accent color
            background:
                Colors
                    .grey[900], // Explicit background color needed by some widgets
            surface: Colors.grey[850], // Color for surfaces like cards, appbars
            onPrimary: Colors.black, // Text/icon color on primary color
            onSecondary: Colors.black,
            onBackground: Colors.white,
            onSurface: Colors.white, // Text/icon color on surface color
            primaryContainer: Colors.teal[800], // Color for themed containers
          ),
        ),
        // themeMode: ThemeMode.dark, // You can explicitly set dark mode if needed, otherwise theme brightness works
        debugShowCheckedModeBanner:
            false, // Hide the debug banner in the corner
        initialRoute: '/splash', // The first route to load
        routes: {
          // Define the navigation routes for the app
          '/splash': (context) => const SplashScreen(), // Splash screen route
          '/library': (context) => const LibraryScreen(), // Main library view
          '/player': (context) => const PlayerScreen(), // Audiobook player view
        },
      ),
    );
  }
}

// ErrorApp widget is removed as we are no longer exiting on failure in this version
