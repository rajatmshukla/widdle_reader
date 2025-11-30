import 'package:flutter/material.dart';
import 'dart:async';
import '../services/simple_audio_service.dart';
import '../models/audiobook.dart';

/// A pill-shaped mini player that appears at the bottom of the library screen
class MiniPlayerWidget extends StatefulWidget {
  const MiniPlayerWidget({super.key});

  @override
  State<MiniPlayerWidget> createState() => _MiniPlayerWidgetState();
}

class _MiniPlayerWidgetState extends State<MiniPlayerWidget>
    with SingleTickerProviderStateMixin {
  final _audioService = SimpleAudioService();
  
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  
  StreamSubscription? _playingSubscription;
  StreamSubscription? _chapterSubscription;
  
  bool _isPlaying = false;
  Audiobook? _currentAudiobook;
  int _currentChapterIndex = 0;

  // Marquee animation
  late ScrollController _scrollController;
  Timer? _scrollTimer;
  bool _shouldScroll = false;

  @override
  void initState() {
    super.initState();
    
    // Slide animation
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    ));
    
    _scrollController = ScrollController();
    
    // Initialize state from audio service
    _currentAudiobook = _audioService.currentAudiobook;
    _currentChapterIndex = _audioService.currentChapterIndex;
    _isPlaying = _audioService.isPlaying;
    
    // Listen to playback state
    _playingSubscription = _audioService.playingStream.listen((playing) {
      debugPrint('MiniPlayer: playingStream update: $playing');
      if (mounted) {
        setState(() => _isPlaying = playing);
      }
    });
    
    // Listen to chapter changes
    _chapterSubscription = _audioService.currentChapterStream.listen((index) {
      debugPrint('MiniPlayer: chapterStream update: $index');
      if (mounted) {
        final wasNull = _currentAudiobook == null;
        setState(() {
          _currentChapterIndex = index;
          _currentAudiobook = _audioService.currentAudiobook;
        });
        
        // Animate in if it was previously hidden and now we have a book
        if (wasNull && _currentAudiobook != null) {
          debugPrint('MiniPlayer: Animate in');
          _slideController.forward();
        }
        
        _startMarqueeScroll();
      }
    });
    
    // Show with animation
    debugPrint('MiniPlayer: Initial state - audiobook: $_currentAudiobook, playing: $_isPlaying');
    if (_currentAudiobook != null) {
      debugPrint('MiniPlayer: Forwarding slide animation');
      _slideController.forward();
      _startMarqueeScroll();
    }
  }

  @override
  void dispose() {
    _playingSubscription?.cancel();
    _chapterSubscription?.cancel();
    _slideController.dispose();
    _scrollController.dispose();
    _scrollTimer?.cancel();
    super.dispose();
  }

  void _startMarqueeScroll() {
    _scrollTimer?.cancel();
    
    if (!mounted) return;
    
    // Wait for widget to build and measure text
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _scrollController.hasClients == false) return;
      
      final maxScroll = _scrollController.position.maxScrollExtent;
      _shouldScroll = maxScroll > 0;
      
      if (_shouldScroll) {
        // Start scrolling after a delay
        _scrollTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
          if (!mounted || !_scrollController.hasClients) {
            timer.cancel();
            return;
          }
          
          final current = _scrollController.offset;
          final max = _scrollController.position.maxScrollExtent;
          
          if (current >= max) {
            // Reset to beginning
            _scrollController.jumpTo(0);
            timer.cancel();
            // Restart after pause
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) _startMarqueeScroll();
            });
          } else {
            _scrollController.animateTo(
              current + 1,
              duration: const Duration(milliseconds: 50),
              curve: Curves.linear,
            );
          }
        });
      }
    });
  }

  void _togglePlayPause() async {
    if (_isPlaying) {
      await _audioService.pause();
    } else {
      await _audioService.play();
    }
  }

  void _skipToPrevious() async {
    await _audioService.skipToPrevious();
  }

  void _skipToNext() async {
    await _audioService.skipToNext();
  }

  void _openFullPlayer() {
    if (_currentAudiobook == null) return;
    
    Navigator.pushNamed(
      context,
      '/player',
      arguments: {
        'audiobook': _currentAudiobook,
        'autoPlay': false,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('MiniPlayer: build called. Audiobook: ${_currentAudiobook?.title}');
    // Don't show if no audiobook is loaded
    if (_currentAudiobook == null) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    
    final chapter = _currentAudiobook!.chapters.isNotEmpty &&
            _currentChapterIndex < _currentAudiobook!.chapters.length
        ? _currentAudiobook!.chapters[_currentChapterIndex]
        : null;

    return SlideTransition(
      position: _slideAnimation,
      child: Padding(
        padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(28),
          color: colorScheme.primaryContainer,
          child: InkWell(
            onTap: _openFullPlayer,
            borderRadius: BorderRadius.circular(28),
            child: Container(
              height: 70,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // Cover Art
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _currentAudiobook!.coverArt != null
                        ? Image.memory(
                            _currentAudiobook!.coverArt!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 56,
                            height: 56,
                            color: colorScheme.primaryContainer,
                            child: Icon(
                              Icons.book,
                              color: colorScheme.onPrimaryContainer,
                              size: 32,
                            ),
                          ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // Scrolling Chapter Name
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Text(
                        chapter?.title ?? 'Unknown Chapter',
                        style: textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onPrimaryContainer,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // Controls
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Previous Chapter
                      IconButton(
                        icon: const Icon(Icons.skip_previous_rounded),
                        iconSize: 32,
                        onPressed: _skipToPrevious,
                        tooltip: 'Previous Chapter',
                        color: colorScheme.onPrimaryContainer,
                      ),
                      
                      // Play/Pause (larger, primary)
                      IconButton(
                        icon: Icon(
                          _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        ),
                        iconSize: 40,
                        onPressed: _togglePlayPause,
                        color: colorScheme.onPrimaryContainer,
                      ),
                      
                      // Next Chapter
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded),
                        iconSize: 32,
                        onPressed: _skipToNext,
                        tooltip: 'Next Chapter',
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
