import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/search_provider.dart';

class SearchBarWidget extends ConsumerStatefulWidget {
  final VoidCallback? onClear;
  
  const SearchBarWidget({
    super.key,
    this.onClear,
  });

  @override
  ConsumerState<SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends ConsumerState<SearchBarWidget>
    with SingleTickerProviderStateMixin {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    // Auto-focus when search bar appears
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _animationController.forward();
    });
    
    // Listen to controller changes for clear button state
    _controller.addListener(() {
      setState(() {}); // Rebuild for clear button visibility
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _controller.clear();
    ref.read(searchProvider.notifier).clearSearch();
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final searchState = ref.watch(searchProvider);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surface.withOpacity(0.95),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: colorScheme.outline.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Search icon
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Icon(
                Icons.search_rounded,
                color: colorScheme.onSurfaceVariant,
                size: 24,
              ),
            ),
            
            // Search text field
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  hintText: 'Search books, authors, or tags...',
                  hintStyle: TextStyle(
                    color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                    fontSize: 16,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 14,
                  ),
                ),
                onChanged: (value) {
                  ref.read(searchProvider.notifier).updateQuery(value);
                },
                onSubmitted: (value) {
                  // Optionally handle search submission
                },
              ),
            ),
            
            // Clear button (only show when there's text)
            if (_controller.text.isNotEmpty || searchState.query.isNotEmpty)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: IconButton(
                  key: const ValueKey('clear_button'),
                  icon: Icon(
                    Icons.clear_rounded,
                    color: colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  onPressed: _clearSearch,
                  tooltip: 'Clear search',
                ),
              ),
            
            // Close search button
            IconButton(
              icon: Icon(
                Icons.keyboard_arrow_up_rounded,
                color: colorScheme.onSurfaceVariant,
                size: 24,
              ),
              onPressed: () {
                _clearSearch();
                _animationController.reverse();
              },
              tooltip: 'Close search',
            ),
          ],
        ),
      ),
    );
  }
}

class SearchResultsWidget extends ConsumerWidget {
  final List<Widget> children;
  final String query;

  const SearchResultsWidget({
    super.key,
    required this.children,
    required this.query,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    if (children.isEmpty && query.trim().isNotEmpty) {
      // No results found
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 64,
                color: colorScheme.onSurfaceVariant.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No results found',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try searching for different keywords\nor check your spelling',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: () {
                  ref.read(searchProvider.notifier).clearSearch();
                },
                icon: const Icon(Icons.clear_all_rounded),
                label: const Text('Clear search'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Search results header
        if (query.trim().isNotEmpty && children.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  '${children.length} result${children.length == 1 ? '' : 's'} for "$query"',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        
        // Search results
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            physics: const BouncingScrollPhysics(),
            itemCount: children.length,
            itemBuilder: (context, index) {
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: children[index],
              );
            },
          ),
        ),
      ],
    );
  }
} 