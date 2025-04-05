import 'package:get_it/get_it.dart'; // Import GetIt
import 'services/audio_handler.dart'; // Import your handler type and init function

// Create a global instance of GetIt
final GetIt locator = GetIt.instance;

/// Registers the singleton AudioHandler instance with GetIt.
/// This function MUST be called AFTER initAudioService has successfully completed.
Future<void> setupLocator() async {
  // First, ensure the audio service itself is initialized (important!)
  // This call should return the already initialized instance if main already called it,
  // or initialize it if somehow missed (though main should handle it).
  // We mostly care that it's initialized *before* registration.
  await initAudioService();

  // Now, register the initialized instance as a singleton in GetIt.
  // Use registerSingleton instead of registerLazySingleton to ensure it exists.
  // The `getAudioHandlerInstance()` function retrieves the globally initialized instance.
  try {
    locator.registerSingleton<MyAudioHandler>(getAudioHandlerInstance());
    print(
      "Locator: MyAudioHandler registered successfully.",
    ); // Use print here for visibility during setup
  } catch (e) {
    print("Locator: ERROR registering MyAudioHandler - $e"); // Use print here
    // Rethrow or handle if registration failure is critical
    rethrow;
  }
}
