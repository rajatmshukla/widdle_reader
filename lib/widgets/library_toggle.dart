import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/tag_provider.dart';

class LibraryToggle extends ConsumerWidget {
  const LibraryToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentMode = ref.watch(libraryModeProvider);
    final screenWidth = MediaQuery.of(context).size.width;

    return Center(
      child: Container(
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
                ref.read(libraryModeProvider.notifier).state = mode;
              }
            },
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
} 