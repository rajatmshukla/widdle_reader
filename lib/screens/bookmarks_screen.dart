import 'package:flutter/material.dart';
import '../models/audiobook.dart';
import '../models/bookmark.dart';
import '../models/chapter.dart';
import '../services/storage_service.dart';
import '../utils/helpers.dart';

class BookmarksScreen extends StatefulWidget {
  final Audiobook audiobook;
  final Function(String, Duration) onBookmarkSelected;

  const BookmarksScreen({
    super.key,
    required this.audiobook,
    required this.onBookmarkSelected,
  });

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  final StorageService _storageService = StorageService();
  List<Bookmark> _bookmarks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    setState(() {
      _isLoading = true;
    });

    final bookmarks = await _storageService.getBookmarks(widget.audiobook.id);
    
    if (mounted) {
      setState(() {
        _bookmarks = bookmarks;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Bookmarks - ${widget.audiobook.title}'),
        actions: [
          if (_bookmarks.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Delete all bookmarks',
              onPressed: () => _confirmDeleteAll(),
            ),
        ],
      ),
      body: _isLoading 
          ? Center(child: CircularProgressIndicator())
          : _bookmarks.isEmpty
              ? _buildEmptyState(colorScheme)
              : _buildBookmarksList(colorScheme),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bookmark_border,
            size: 64,
            color: colorScheme.primary.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No bookmarks yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add bookmarks while listening to easily\nreturn to important parts of your audiobook',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookmarksList(ColorScheme colorScheme) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _bookmarks.length,
      itemBuilder: (context, index) {
        final bookmark = _bookmarks[index];
        
        // Find chapter title for this bookmark
        final chapter = widget.audiobook.chapters.firstWhere(
          (c) => c.id == bookmark.chapterId,
          orElse: () => Chapter(
            id: bookmark.chapterId,
            title: 'Unknown Chapter',
            audiobookId: widget.audiobook.id,
          ),
        );
        
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          elevation: 2,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: colorScheme.primary,
              child: const Icon(Icons.bookmark, color: Colors.white),
            ),
            title: Text(bookmark.name),
            subtitle: Text(
              '${chapter.title} • ${formatDetailedDuration(bookmark.position)}',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Rename',
                  onPressed: () => _showRenameDialog(bookmark),
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: 'Delete',
                  onPressed: () => _confirmDelete(bookmark),
                ),
              ],
            ),
            onTap: () {
              // Return to player at the bookmark position
              widget.onBookmarkSelected(bookmark.chapterId, bookmark.position);
              Navigator.pop(context);
            },
          ),
        );
      },
    );
  }

  Future<void> _showRenameDialog(Bookmark bookmark) async {
    final textController = TextEditingController(text: bookmark.name);
    
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Bookmark'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Bookmark name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () async {
              final newName = textController.text.trim();
              if (newName.isNotEmpty) {
                final updatedBookmark = bookmark.copyWith(name: newName);
                await _storageService.saveBookmark(updatedBookmark);
                if (mounted) {
                  Navigator.pop(context);
                  _loadBookmarks();
                }
              }
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(Bookmark bookmark) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Bookmark'),
        content: Text('Are you sure you want to delete "${bookmark.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () async {
              await _storageService.deleteBookmark(
                widget.audiobook.id,
                bookmark.id,
              );
              if (mounted) {
                Navigator.pop(context);
                _loadBookmarks();
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAll() async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Bookmarks'),
        content: Text(
          'Are you sure you want to delete all ${_bookmarks.length} bookmarks?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () async {
              await _storageService.deleteAllBookmarks(widget.audiobook.id);
              if (mounted) {
                Navigator.pop(context);
                _loadBookmarks();
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('DELETE ALL'),
          ),
        ],
      ),
    );
  }
} 