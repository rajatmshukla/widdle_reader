import 'dart:async';
import 'package:flutter/material.dart';
import '../services/simple_audio_service.dart';
import '../models/audiobook.dart';

/// A compact mini player for the reader screen.
/// Shows current chapter and play/pause control.
class ReaderMiniPlayer extends StatefulWidget {
  final VoidCallback? onTap;

  const ReaderMiniPlayer({
    super.key,
    this.onTap,
  });

  @override
  State<ReaderMiniPlayer> createState() => _ReaderMiniPlayerState();
}

class _ReaderMiniPlayerState extends State<ReaderMiniPlayer> {
  final _audioService = SimpleAudioService();

  StreamSubscription? _playingSubscription;
  StreamSubscription? _chapterSubscription;
  StreamSubscription? _audiobookSubscription;

  bool _isPlaying = false;
  Audiobook? _currentAudiobook;
  int _currentChapterIndex = 0;

  @override
  void initState() {
    super.initState();

    // Initialize state
    _currentAudiobook = _audioService.currentAudiobook;
    _currentChapterIndex = _audioService.currentChapterIndex;
    _isPlaying = _audioService.isPlaying;

    // Listen to state changes
    _playingSubscription = _audioService.playingStream.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });

    _chapterSubscription = _audioService.currentChapterStream.listen((index) {
      if (mounted) {
        setState(() {
          _currentChapterIndex = index;
          _currentAudiobook = _audioService.currentAudiobook;
        });
      }
    });

    _audiobookSubscription = _audioService.audiobookStream.listen((audiobook) {
      if (mounted) setState(() => _currentAudiobook = audiobook);
    });
  }

  @override
  void dispose() {
    _playingSubscription?.cancel();
    _chapterSubscription?.cancel();
    _audiobookSubscription?.cancel();
    super.dispose();
  }

  void _togglePlayPause() async {
    if (_isPlaying) {
      await _audioService.pause();
    } else {
      await _audioService.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Don't show if no audiobook is loaded
    if (_currentAudiobook == null) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final chapter = _currentAudiobook!.chapters.isNotEmpty &&
            _currentChapterIndex < _currentAudiobook!.chapters.length
        ? _currentAudiobook!.chapters[_currentChapterIndex]
        : null;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        height: 56,
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Cover art
            Padding(
              padding: const EdgeInsets.all(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _currentAudiobook!.coverArt != null
                    ? Image.memory(
                        _currentAudiobook!.coverArt!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 40,
                        height: 40,
                        color: colorScheme.primary.withOpacity(0.2),
                        child: Icon(
                          Icons.headphones,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                      ),
              ),
            ),

            // Chapter name
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chapter?.title ?? 'Unknown Chapter',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      color: colorScheme.onPrimaryContainer,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _currentAudiobook!.title,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onPrimaryContainer.withOpacity(0.7),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Tap hint
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                'Listen',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onPrimaryContainer.withOpacity(0.5),
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: colorScheme.onPrimaryContainer.withOpacity(0.5),
              size: 20,
            ),

            // Play/Pause button
            IconButton(
              icon: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: colorScheme.onPrimaryContainer,
              ),
              iconSize: 28,
              onPressed: _togglePlayPause,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
