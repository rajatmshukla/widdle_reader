import 'package:flutter/material.dart';
import '../models/audiobook.dart';
import '../models/bookmark.dart';
import '../services/storage_service.dart';
import '../utils/helpers.dart';
import '../models/chapter.dart';
import '../services/pulse_sync_service.dart';

class AddBookmarkDialog extends StatefulWidget {
  final Audiobook audiobook;
  final String currentChapterId;
  final Duration currentPosition;

  const AddBookmarkDialog({
    super.key,
    required this.audiobook,
    required this.currentChapterId,
    required this.currentPosition,
  });

  @override
  State<AddBookmarkDialog> createState() => _AddBookmarkDialogState();
}

class _AddBookmarkDialogState extends State<AddBookmarkDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final StorageService _storageService = StorageService();
  bool _isLoading = false;
  late String _defaultBookmarkName;

  @override
  void initState() {
    super.initState();
    // Find the current chapter for display purposes only
    final chapter = widget.audiobook.chapters.firstWhere(
      (c) => c.id == widget.currentChapterId,
      orElse: () => Chapter(
        id: widget.currentChapterId,
        title: 'Unknown Chapter',
        audiobookId: widget.audiobook.id,
        sourcePath: widget.currentChapterId, // Fallback
      ),
    );
    
    // Create comprehensive default bookmark name: Book name + Chapter + Position
    final timeString = formatDetailedDuration(widget.currentPosition);
    
    // Include chapter info if there are multiple chapters
    if (widget.audiobook.chapters.length > 1) {
      _defaultBookmarkName = '${widget.audiobook.title} - ${chapter.title} - $timeString';
    } else {
      // For single chapter audiobooks, just use book name + position
      _defaultBookmarkName = '${widget.audiobook.title} - $timeString';
    }
    
    // Leave the text field empty so the default name shows as placeholder
    _nameController.text = '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveBookmark() async {
    setState(() {
      _isLoading = true;
    });

    // Use custom name if provided, otherwise use default name
    final bookmarkName = _nameController.text.trim().isEmpty 
        ? _defaultBookmarkName 
        : _nameController.text.trim();

    final bookmark = Bookmark.create(
      audiobookId: widget.audiobook.id,
      chapterId: widget.currentChapterId,
      position: widget.currentPosition,
      name: bookmarkName,
    );

    await _storageService.saveBookmark(bookmark);
    
    // Pulse out bookmark
    PulseSyncService().pulseOut();
    
    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    // Find chapter title for display purposes
    final chapter = widget.audiobook.chapters.firstWhere(
      (c) => c.id == widget.currentChapterId,
      orElse: () => Chapter(
        id: widget.currentChapterId,
        title: 'Unknown Chapter',
        audiobookId: widget.audiobook.id,
        sourcePath: widget.currentChapterId, // Fallback
      ),
    );
    
    return AlertDialog(
      title: Text('Add Bookmark'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chapter: ${chapter.title}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              'Position: ${formatDetailedDuration(widget.currentPosition)}',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Bookmark Name',
                hintText: _defaultBookmarkName,
                border: OutlineInputBorder(),
                helperText: 'Leave empty to use: Book - Chapter - Position',
              ),
              autofocus: true,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _saveBookmark(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context, false),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _saveBookmark,
          child: _isLoading 
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('SAVE'),
        ),
      ],
    );
  }
} 