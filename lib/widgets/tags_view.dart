import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;

import '../models/tag.dart';
import '../models/audiobook.dart';
import '../providers/tag_provider.dart';
import '../providers/audiobook_provider.dart';
import '../widgets/audiobook_tile.dart';
import '../utils/responsive_utils.dart';
import '../services/storage_service.dart';

class TagsView extends ConsumerStatefulWidget {
  const TagsView({super.key});

  @override
  ConsumerState<TagsView> createState() => _TagsViewState();
}

class _TagsViewState extends ConsumerState<TagsView> {
  String? _selectedTag;

  // Function to check for and load last played position
  Future<void> _loadLastPositionAndNavigate(
    BuildContext context,
    Audiobook audiobook,
    AudiobookProvider audiobookProvider,
  ) async {
    // Check mounted state BEFORE async gap
    if (!context.mounted) return;

    final storageService = StorageService();
    final lastPositionData = await storageService.loadLastPosition(
      audiobook.id,
    );

    // Check mounted state AFTER async gap
    if (!context.mounted) return;

    // Record that this book is being played (will update timestamps and sort order)
    await audiobookProvider.recordBookPlayed(audiobook.id);

    // Prepare arguments for the player screen
    Map<String, dynamic> arguments = {
      'audiobook': audiobook,
      'autoPlay': false, // Explicitly set autoPlay to false
    };

    if (lastPositionData != null) {
      arguments['startChapterId'] = lastPositionData['chapterId'];
      arguments['startPosition'] = lastPositionData['position'];
      debugPrint(
        "Found last position for ${audiobook.title}: Chapter ${lastPositionData['chapterId']}, Position ${lastPositionData['position']}",
      );
    } else {
      debugPrint(
        "No last position found for ${audiobook.title}, starting from beginning.",
      );
    }

    // Use Hero animation for smoother transitions
    final result = await Navigator.pushNamed(
      context,
      '/player',
      arguments: arguments,
    );

    // When returning from player screen, force refresh and update UI
    if (context.mounted) {
      // Notify listeners to trigger UI update without a full reload
      audiobookProvider.refreshUI();

      // Force update TagsView widgets
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedTag != null) {
      return _buildTaggedBooksView();
    } else {
      return _buildTagsListView();
    }
  }

  Widget _buildTagsListView() {
    final colorScheme = Theme.of(context).colorScheme;
    final tags = ref.watch(syncedTagProvider);
    final sortOption = ref.watch(tagSortOptionProvider);

    return Column(
      children: [
        // Tags list (removed sort dropdown)
        Expanded(
          child: tags.when(
            data: (tagList) => _buildTagsList(tagList, sortOption, colorScheme),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => _buildErrorView(error.toString()),
          ),
        ),
      ],
    );
  }

  Widget _buildTagsList(List<Tag> tagList, TagSortOption sortOption, ColorScheme colorScheme) {
    if (tagList.isEmpty) {
      return _buildEmptyTagsView(colorScheme);
    }

    // Sort the tags directly using the provided tagList
    final List<Tag> sortedTags = List.from(tagList);

    // Always keep Favorites first
    final favorites = sortedTags.where((tag) => tag.isFavorites).toList();
    final others = sortedTags.where((tag) => !tag.isFavorites).toList();

    switch (sortOption) {
      case TagSortOption.alphabeticalAZ:
        others.sort((a, b) => a.name.compareTo(b.name));
        break;
      case TagSortOption.alphabeticalZA:
        others.sort((a, b) => b.name.compareTo(a.name));
        break;
      case TagSortOption.recentlyUsed:
        others.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
        break;
      case TagSortOption.recentlyCreated:
        others.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }

    final finalSortedTags = [...favorites, ...others];

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: finalSortedTags.length,
      itemBuilder: (context, index) {
        final tag = finalSortedTags[index];
        return _buildTagTile(tag, colorScheme);
      },
    );
  }

  Widget _buildTagTile(Tag tag, ColorScheme colorScheme) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: tag.isFavorites 
              ? const Color(0xFFB71C1C) // Deep red background for favorites
              : colorScheme.primaryContainer,
          child: Icon(
            tag.isFavorites ? Icons.favorite : Icons.label,
            color: tag.isFavorites 
                ? Colors.white // White icon on deep red background
                : colorScheme.onPrimaryContainer,
            size: 20,
          ),
        ),
        title: Text(
          tag.name,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: tag.isFavorites ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        subtitle: Text(
          '${tag.bookCount} book${tag.bookCount == 1 ? '' : 's'}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: tag.bookCount > 0 ? () {
          setState(() {
            _selectedTag = tag.name;
          });
          // Update tag usage
          ref.read(tagProvider.notifier).updateTagUsage(tag.name);
        } : null,
        onLongPress: !tag.isFavorites ? () {
          _showTagOptionsDialog(tag);
        } : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildTaggedBooksView() {
    final colorScheme = Theme.of(context).colorScheme;
    final audiobookTags = ref.watch(audiobookTagsProvider);
    final audiobookProvider = provider.Provider.of<AudiobookProvider>(context, listen: false);
    
    // Get audiobooks with the selected tag
    final taggedAudiobookIds = audiobookTags.entries
        .where((entry) => entry.value.contains(_selectedTag!))
        .map((entry) => entry.key)
        .toSet();
    
    final taggedAudiobooks = audiobookProvider.audiobooks
        .where((book) => taggedAudiobookIds.contains(book.id))
        .toList();

    return Column(
      children: [
        // Header with back button
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedTag = null;
                  });
                },
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to tags',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedTag!,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${taggedAudiobooks.length} book${taggedAudiobooks.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Books list with responsive layout
        Expanded(
          child: taggedAudiobooks.isEmpty
              ? _buildEmptyTaggedBooksView(colorScheme)
              : ResponsiveUtils.isLandscape(context)
                  ? _buildTaggedBooksGrid(taggedAudiobooks, audiobookProvider)
                  : _buildTaggedBooksList(taggedAudiobooks, audiobookProvider),
        ),
      ],
    );
  }

  // Grid view for landscape orientation in tagged books
  Widget _buildTaggedBooksGrid(List<Audiobook> taggedAudiobooks, AudiobookProvider audiobookProvider) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Calculate how many items to show per row based on screen width
    final crossAxisCount = screenWidth > 1200 ? 4 : (screenWidth > 800 ? 3 : 2);

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 1.8,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: taggedAudiobooks.length,
      itemBuilder: (context, index) {
        final audiobook = taggedAudiobooks[index];
        return GestureDetector(
          onTap: () => _loadLastPositionAndNavigate(context, audiobook, audiobookProvider),
          onLongPress: () {
            _showRemoveFromTagDialog(audiobook, audiobookProvider.getTitleForAudiobook(audiobook));
          },
          child: AudiobookTile(
            audiobook: audiobook,
            customTitle: audiobookProvider.getTitleForAudiobook(audiobook),
          ),
        );
      },
    );
  }

  // List view for portrait orientation in tagged books
  Widget _buildTaggedBooksList(List<Audiobook> taggedAudiobooks, AudiobookProvider audiobookProvider) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      physics: const BouncingScrollPhysics(),
      itemCount: taggedAudiobooks.length,
      itemBuilder: (context, index) {
        final audiobook = taggedAudiobooks[index];
        return GestureDetector(
          onTap: () => _loadLastPositionAndNavigate(context, audiobook, audiobookProvider),
          onLongPress: () {
            _showRemoveFromTagDialog(audiobook, audiobookProvider.getTitleForAudiobook(audiobook));
          },
          child: AudiobookTile(
            audiobook: audiobook,
            customTitle: audiobookProvider.getTitleForAudiobook(audiobook),
          ),
        );
      },
    );
  }

  // Show tag options dialog (rename or delete)
  void _showTagOptionsDialog(Tag tag) {
    final colorScheme = Theme.of(context).colorScheme;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Manage "${tag.name}"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.edit, color: colorScheme.primary),
              title: const Text('Rename Tag'),
              onTap: () {
                Navigator.pop(context);
                _showRenameTagDialog(tag);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete, color: colorScheme.error),
              title: const Text('Delete Tag'),
              subtitle: Text('Will remove from ${tag.bookCount} book${tag.bookCount == 1 ? '' : 's'}'),
              onTap: () {
                Navigator.pop(context);
                _showDeleteTagDialog(tag);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  // Show rename tag dialog
  void _showRenameTagDialog(Tag tag) {
    final colorScheme = Theme.of(context).colorScheme;
    final controller = TextEditingController(text: tag.name);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Tag'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Tag Name',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;
              
              Navigator.pop(context);
              try {
                await ref.read(tagProvider.notifier).renameTag(tag.name, newName);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Renamed "${tag.name}" to "$newName"'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error renaming tag: $e'),
                      backgroundColor: colorScheme.error,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  );
                }
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  // Show delete tag confirmation dialog
  void _showDeleteTagDialog(Tag tag) {
    final colorScheme = Theme.of(context).colorScheme;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Tag'),
        content: Text(
          'Are you sure you want to delete the tag "${tag.name}"?\n\n'
          'This will remove the tag from all ${tag.bookCount} book${tag.bookCount == 1 ? '' : 's'} '
          'but will not delete the books themselves.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref.read(tagProvider.notifier).deleteTag(tag.name);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Deleted tag "${tag.name}"'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      action: SnackBarAction(
                        label: 'Dismiss',
                        onPressed: () {
                          // Do nothing, just dismiss
                        },
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error deleting tag: $e'),
                      backgroundColor: colorScheme.error,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.errorContainer,
              foregroundColor: colorScheme.onErrorContainer,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Show remove book from tag confirmation dialog
  void _showRemoveFromTagDialog(Audiobook audiobook, String customTitle) {
    final colorScheme = Theme.of(context).colorScheme;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove from ${_selectedTag!}'),
        content: Text(
          'Are you sure you want to remove "$customTitle" from the "${_selectedTag!}" tag?\n\n'
          'The book will remain in your library and other tags.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () async {
              Navigator.pop(context);
              try {
                // Remove the book from the current tag
                await ref.read(audiobookTagsProvider.notifier).removeTagFromAudiobook(
                  audiobook.id, 
                  _selectedTag!,
                );
                
                                 // Update tag usage count
                 final currentAudiobookTags = ref.read(audiobookTagsProvider);
                 await ref.read(tagProvider.notifier).recalculateTagCounts(currentAudiobookTags);
                
                if (mounted) {
                  // Update the UI by rebuilding the widget
                  setState(() {});
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Removed "$customTitle" from "${_selectedTag!}"'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      action: SnackBarAction(
                        label: 'Dismiss',
                        onPressed: () {
                          // Do nothing, just dismiss
                        },
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error removing book from tag: $e'),
                      backgroundColor: colorScheme.error,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.errorContainer,
              foregroundColor: colorScheme.onErrorContainer,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTagsView(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.label_outline,
                size: 64,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No tags created yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Create tags to organize your audiobooks.\nTap the ❤️ icon on books to add them to favorites.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                ref.read(libraryModeProvider.notifier).updateLibraryMode(LibraryMode.library);
              },
              icon: const Icon(Icons.library_books),
              label: const Text('Browse Library'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyTaggedBooksView(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.menu_book_outlined,
                size: 64,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No books with this tag',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Books you tag with "${_selectedTag!}" will appear here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _selectedTag = null;
                });
                ref.read(libraryModeProvider.notifier).updateLibraryMode(LibraryMode.library);
              },
              icon: const Icon(Icons.library_books),
              label: const Text('Browse Library'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(String error) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: colorScheme.error,
            ),
            const SizedBox(height: 24),
            Text(
              'Error loading tags',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                ref.read(tagProvider.notifier).loadTags();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
} 