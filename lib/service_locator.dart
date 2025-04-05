// lib/service_locator.dart
import 'package:flutter/foundation.dart';
import 'services/audio_handler.dart';

// Single class to manage all global services
class ServiceLocator {
  // Singleton pattern
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  ServiceLocator._internal();

  // Flag to track initialization status
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // Audio handler reference
  MyAudioHandler? _audioHandler;
  MyAudioHandler? get audioHandler => _audioHandler;

  // Initialize all services
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint("ServiceLocator: Already initialized!");
      return;
    }

    debugPrint("ServiceLocator: Starting initialization...");

    try {
      // Initialize audio service
      _audioHandler = await initAudioService();
      _isInitialized = true;
      debugPrint("ServiceLocator: Successfully initialized all services!");
    } catch (e, stackTrace) {
      debugPrint("ServiceLocator: Initialization failed: $e");
      debugPrint("$stackTrace");
      rethrow; // Propagate the error to the caller
    }
  }

  // Get the audio handler safely
  MyAudioHandler getAudioHandler() {
    if (!_isInitialized || _audioHandler == null) {
      throw Exception(
        "Audio handler not initialized. Call ServiceLocator().initialize() first.",
      );
    }
    return _audioHandler!;
  }
}

// Global instance for easy access
final serviceLocator = ServiceLocator();
