import 'package:flutter/material.dart';
import '../models/audiobook.dart';
import '../models/bookmark.dart';
import '../services/storage_service.dart';
import '../utils/helpers.dart';
import '../models/chapter.dart';

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
      ),
    );
    
    // Leave the text field empty to prompt user input
    // The timestamp info will be displayed separately
    _nameController.text = '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveBookmark() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      final bookmark = Bookmark.create(
        audiobookId: widget.audiobook.id,
        chapterId: widget.currentChapterId,
        position: widget.currentPosition,
        name: _nameController.text.trim(),
      );

      await _storageService.saveBookmark(bookmark);
      
      if (mounted) {
        Navigator.pop(context, true);
      }
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
                labelText: 'Bookmark Note',
                hintText: 'Add a note to help you remember this spot',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              textInputAction: TextInputAction.done,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please add a note for this bookmark';
                }
                return null;
              },
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