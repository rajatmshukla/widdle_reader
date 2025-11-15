import 'dart:async';
import 'package:flutter/material.dart';
import '../services/simple_audio_service.dart';

class SleepTimerProvider extends ChangeNotifier {
  Timer? _sleepTimer;
  Duration? _sleepTimerDuration;
  Duration? _remainingTime;
  bool _isActive = false;
  
  // Stream controller to broadcast timer updates
  final StreamController<Duration> _remainingTimeController = StreamController<Duration>.broadcast();
  
  // Singleton instance
  static final SleepTimerProvider _instance = SleepTimerProvider._internal();
  
  // Factory constructor
  factory SleepTimerProvider() => _instance;
  
  // Internal constructor
  SleepTimerProvider._internal();
  
  // Getters
  bool get isActive => _isActive;
  Duration? get remainingTime => _remainingTime;
  Duration? get totalDuration => _sleepTimerDuration;
  Stream<Duration> get remainingTimeStream => _remainingTimeController.stream;
  
  // Start timer
  void startTimer(Duration duration) {
    // Cancel existing timer if any
    cancelTimer();
    
    _sleepTimerDuration = duration;
    _remainingTime = duration;
    _isActive = true;
    
    // Emit initial value to stream
    _remainingTimeController.add(_remainingTime!);
    
    // Create a timer that ticks every second
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingTime != null) {
        final newRemaining = _remainingTime! - const Duration(seconds: 1);
        _remainingTime = newRemaining.isNegative ? Duration.zero : newRemaining;
        
        // Emit to stream
        _remainingTimeController.add(_remainingTime!);
        
        // Notify listeners of the updated time
        notifyListeners();
        
        // When timer reaches zero
        if (_remainingTime == Duration.zero) {
          _handleTimerEnd();
        }
      }
    });
    
    notifyListeners();
  }
  
  // Handle timer end
  void _handleTimerEnd() {
    cancelTimer();
    
    // Pause audio playback
    final audioService = SimpleAudioService();
    audioService.pause();
    audioService.saveCurrentPosition();
  }
  
  // Cancel timer
  void cancelTimer() {
    if (_sleepTimer != null) {
      _sleepTimer!.cancel();
      _sleepTimer = null;
      _isActive = false;
      _remainingTime = null;
      _sleepTimerDuration = null;
      
      notifyListeners();
    }
  }
  
  // Format remaining time for display
  String formatRemainingTime() {
    if (_remainingTime == null) return '';
    
    final minutes = _remainingTime!.inMinutes;
    final seconds = _remainingTime!.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
  
  @override
  void dispose() {
    _remainingTimeController.close();
    super.dispose();
  }
} 