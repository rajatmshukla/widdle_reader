import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/audiobook.dart';
import '../models/tag.dart';
import '../providers/tag_provider.dart';

class TagAssignmentDialog extends ConsumerStatefulWidget {
  final Audiobook audiobook;
  final String customTitle;

  const TagAssignmentDialog({
    super.key,
    required this.audiobook,
    required this.customTitle,
  });

  @override
  ConsumerState<TagAssignmentDialog> createState() => _TagAssignmentDialogState();
}

class _TagAssignmentDialogState extends ConsumerState<TagAssignmentDialog> {
  final TextEditingController _newTagController = TextEditingController();
  bool _isCreatingTag = false;
  String? _errorMessage;

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tags = ref.watch(tagProvider);
    final audiobookTags = ref.watch(audiobookTagsProvider);
    final currentBookTags = audiobookTags[widget.audiobook.id] ?? <String>{};

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              'Manage Tags',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'for "${widget.customTitle}"',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),

            // Tags list
            Flexible(
              child: tags.when(
                data: (tagList) => _buildTagsList(tagList, currentBookTags, colorScheme),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => Text(
                  'Error loading tags: $error',
                  style: TextStyle(color: colorScheme.error),
                ),
              ),
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Create new tag section
            if (_isCreatingTag) _buildCreateTagSection(colorScheme) else _buildCreateTagButton(colorScheme),

            // Error message
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(
                  color: colorScheme.error,
                  fontSize: 14,
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _updateTagCounts();
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagsList(List<Tag> tagList, Set<String> currentBookTags, ColorScheme colorScheme) {
    if (tagList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.label_outline,
              size: 48,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No tags available',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first tag below',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: tagList.length,
      itemBuilder: (context, index) {
        final tag = tagList[index];
        final isSelected = currentBookTags.contains(tag.name);
        
        return CheckboxListTile(
          value: isSelected,
          onChanged: (bool? value) => _toggleTag(tag.name, value ?? false),
          title: Row(
            children: [
              if (tag.isFavorites) ...[
                Icon(
                  Icons.favorite,
                  size: 18,
                  color: colorScheme.error,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  tag.name,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: tag.isFavorites ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          subtitle: tag.bookCount > 0
              ? Text(
                  '${tag.bookCount} book${tag.bookCount == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                )
              : null,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          tileColor: isSelected ? colorScheme.primaryContainer.withOpacity(0.3) : null,
        );
      },
    );
  }

  Widget _buildCreateTagButton(ColorScheme colorScheme) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          setState(() {
            _isCreatingTag = true;
            _errorMessage = null;
          });
        },
        icon: const Icon(Icons.add),
        label: const Text('Create New Tag'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildCreateTagSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Textbox first as requested
        TextField(
          controller: _newTagController,
          decoration: InputDecoration(
            labelText: 'New Tag Name',
            hintText: 'Enter tag name',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          textCapitalization: TextCapitalization.words,
          maxLength: 30,
          buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
          onSubmitted: (_) => _createNewTag(),
          autofocus: true,
        ),
        const SizedBox(height: 12),
        // Save and X buttons after textbox
        Row(
          children: [
            FilledButton.icon(
              onPressed: _createNewTag,
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Save'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              onPressed: () {
                setState(() {
                  _isCreatingTag = false;
                  _newTagController.clear();
                  _errorMessage = null;
                });
              },
              icon: const Icon(Icons.close),
              tooltip: 'Cancel',
            ),
          ],
        ),
      ],
    );
  }

  void _toggleTag(String tagName, bool isSelected) {
    final tagNotifier = ref.read(audiobookTagsProvider.notifier);
    
    if (isSelected) {
      tagNotifier.addTagToAudiobook(widget.audiobook.id, tagName);
      
      // Update tag usage
      ref.read(tagProvider.notifier).updateTagUsage(tagName);
    } else {
      tagNotifier.removeTagFromAudiobook(widget.audiobook.id, tagName);
    }
  }

  void _createNewTag() async {
    final tagName = _newTagController.text.trim();
    
    if (tagName.isEmpty) {
      setState(() {
        _errorMessage = 'Tag name cannot be empty';
      });
      return;
    }

    try {
      // Create the tag
      await ref.read(tagProvider.notifier).createTag(tagName);
      
      // Clear the input and hide the creation form
      _newTagController.clear();
      setState(() {
        _isCreatingTag = false;
        _errorMessage = null;
      });

      // Auto-assign the new tag to the current audiobook
      await ref.read(audiobookTagsProvider.notifier).addTagToAudiobook(widget.audiobook.id, tagName);
      
    } catch (error) {
      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _updateTagCounts() async {
    final tagNotifier = ref.read(tagProvider.notifier);
    final audiobookTags = ref.read(audiobookTagsProvider);
    final tags = ref.read(tagProvider).asData?.value ?? [];

    // Update book counts for all tags
    for (final tag in tags) {
      final bookCount = audiobookTags.entries
          .where((entry) => entry.value.contains(tag.name))
          .length;
      
      await tagNotifier.updateTagBookCount(tag.name, bookCount);
    }
  }
} 