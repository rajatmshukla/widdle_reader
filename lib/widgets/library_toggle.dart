import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;

import '../providers/tag_provider.dart';
import '../providers/audiobook_provider.dart';
import '../models/tag.dart';

class LibraryToggle extends ConsumerWidget {
  const LibraryToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentMode = ref.watch(libraryModeProvider);
    final screenWidth = MediaQuery.of(context).size.width;

    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Main toggle container
          Container(
        width: screenWidth * 2 / 3, // 2/3 of screen width
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            _buildToggleButton(
              context: context,
              ref: ref,
              mode: LibraryMode.library,
              label: 'Library',
              icon: Icons.auto_stories,
              isSelected: currentMode == LibraryMode.library,
              colorScheme: colorScheme,
            ),
            _buildToggleButton(
              context: context,
              ref: ref,
              mode: LibraryMode.tags,
              label: 'Tags',
              icon: Icons.local_offer,
              isSelected: currentMode == LibraryMode.tags,
              colorScheme: colorScheme,
            ),
          ],
        ),
          ),
          
          // Sort button
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _showSortMenu(context, ref, currentMode, colorScheme),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    Icons.sort_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton({
    required BuildContext context,
    required WidgetRef ref,
    required LibraryMode mode,
    required String label,
    required IconData icon,
    required bool isSelected,
    required ColorScheme colorScheme,
  }) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              if (!isSelected) {
                ref.read(libraryModeProvider.notifier).updateLibraryMode(mode);
              }
            },
            onLongPress: mode == LibraryMode.library ? () => _handleLibraryLongPress(context, ref) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: isSelected 
                        ? colorScheme.onPrimary 
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSelected 
                          ? colorScheme.onPrimary 
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Show sort menu based on current mode
  void _showSortMenu(BuildContext context, WidgetRef ref, LibraryMode currentMode, ColorScheme colorScheme) {
    if (currentMode == LibraryMode.library) {
      _showLibrarySortMenu(context, ref, colorScheme);
    } else {
      _showTagSortMenu(context, ref, colorScheme);
    }
  }

  /// Show library sort options
  void _showLibrarySortMenu(BuildContext context, WidgetRef ref, ColorScheme colorScheme) {
    final currentSort = ref.read(librarySortOptionProvider);
    
    showMenu<LibrarySortOption>(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.of(context).size.width - 200,
        kToolbarHeight + 100,
        20,
        0,
      ),
      items: LibrarySortOption.values.map((option) {
        return PopupMenuItem<LibrarySortOption>(
          value: option,
          child: Row(
            children: [
              Icon(
                _getLibrarySortIcon(option),
                size: 20,
                color: option == currentSort ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  option.displayName,
                  style: TextStyle(
                    color: option == currentSort ? colorScheme.primary : colorScheme.onSurface,
                    fontWeight: option == currentSort ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (option == currentSort)
                Icon(
                  Icons.check,
                  size: 16,
                  color: colorScheme.primary,
                ),
            ],
          ),
        );
      }).toList(),
    ).then((selectedOption) {
      if (selectedOption != null) {
        ref.read(librarySortOptionProvider.notifier).updateSortOption(selectedOption);
      }
    });
  }

  /// Show tag sort options  
  void _showTagSortMenu(BuildContext context, WidgetRef ref, ColorScheme colorScheme) {
    final currentSort = ref.read(tagSortOptionProvider);
    
    showMenu<TagSortOption>(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.of(context).size.width - 200,
        kToolbarHeight + 100,
        20,
        0,
      ),
      items: TagSortOption.values.map((option) {
        return PopupMenuItem<TagSortOption>(
          value: option,
          child: Row(
            children: [
              Icon(
                _getTagSortIcon(option),
                size: 20,
                color: option == currentSort ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  option.displayName,
                  style: TextStyle(
                    color: option == currentSort ? colorScheme.primary : colorScheme.onSurface,
                    fontWeight: option == currentSort ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (option == currentSort)
                Icon(
                  Icons.check,
                  size: 16,
                  color: colorScheme.primary,
                ),
            ],
          ),
        );
      }).toList(),
    ).then((selectedOption) {
      if (selectedOption != null) {
        ref.read(tagSortOptionProvider.notifier).updateSortOption(selectedOption);
      }
    });
  }

  /// Get icon for library sort options
  IconData _getLibrarySortIcon(LibrarySortOption option) {
    switch (option) {
      case LibrarySortOption.alphabeticalAZ:
      case LibrarySortOption.alphabeticalZA:
        return Icons.sort_by_alpha;
      case LibrarySortOption.authorAZ:
      case LibrarySortOption.authorZA:
        return Icons.person;
      case LibrarySortOption.dateAddedNewest:
      case LibrarySortOption.dateAddedOldest:
        return Icons.schedule;
      case LibrarySortOption.lastPlayedRecent:
      case LibrarySortOption.lastPlayedOldest:
        return Icons.play_circle_outline;
      case LibrarySortOption.series:
        return Icons.library_books;
      case LibrarySortOption.completionStatus:
        return Icons.check_circle_outline;
    }
  }

  /// Get icon for tag sort options
  IconData _getTagSortIcon(TagSortOption option) {
    switch (option) {
      case TagSortOption.alphabeticalAZ:
      case TagSortOption.alphabeticalZA:
        return Icons.sort_by_alpha;
      case TagSortOption.recentlyUsed:
        return Icons.access_time;
      case TagSortOption.recentlyCreated:
        return Icons.fiber_new;
    }
  }

  /// Handle long press on Library button to trigger comprehensive rescan
  void _handleLibraryLongPress(BuildContext context, WidgetRef ref) {
    final audioBookProvider = provider.Provider.of<AudiobookProvider>(context, listen: false);
    
    // Provide haptic feedback
    HapticFeedback.mediumImpact();
    
    // Show confirmation dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Refresh Library'),
        content: const Text(
          'This will rescan all audiobook folders and detect any changes, '
          'including renamed or moved folders. This may take a few moments.\n\n'
          'Continue?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              
              // Show loading snackbar
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).colorScheme.onInverseSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text('Refreshing library...'),
                    ],
                  ),
                  duration: const Duration(seconds: 3),
                ),
              );
              
              try {
                // Trigger comprehensive sync with tag updates
                await audioBookProvider.performComprehensiveSync(ref);
                
                // Show success message
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Theme.of(context).colorScheme.onInverseSurface,
                            size: 16,
                          ),
                          const SizedBox(width: 12),
                          const Text('Library refreshed successfully'),
                        ],
                      ),
                      backgroundColor: Theme.of(context).colorScheme.inverseSurface,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                // Show error message
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error refreshing library: $e'),
                      backgroundColor: Theme.of(context).colorScheme.error,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              }
            },
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
} 