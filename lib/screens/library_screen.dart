import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode
import 'package:provider/provider.dart' as provider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../providers/audiobook_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/sleep_timer_provider.dart';
import '../providers/tag_provider.dart';
import '../providers/search_provider.dart';
import '../widgets/audiobook_tile.dart';
import '../widgets/app_logo.dart';
import '../widgets/countdown_timer_widget.dart';
import '../widgets/library_toggle.dart';
import '../widgets/tags_view.dart';
import '../widgets/tag_assignment_dialog.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/detailed_loading_widget.dart';
import '../models/audiobook.dart';
import '../models/tag.dart';
import '../services/storage_service.dart';
import '../services/simple_audio_service.dart';
import '../services/android_auto_manager.dart';
import '../theme.dart';
import '../utils/responsive_utils.dart';

// CRITICAL FIX: Add release-safe logging for library screen
void _logDebug(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
  // Removed release mode logging to improve performance
}

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _androidAutoInitialized = false;
  
  @override  
  void initState() {    
    super.initState();    
    // Register to detect when app becomes active    
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize animation controller
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    
    _animationController.forward();
    
    // Initialize Android Auto with providers
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAndroidAuto();
    });
  }
  
  /// Initialize Android Auto with full provider access
  /// NOTE: This is redundant - main.dart already initializes AndroidAutoManager
  /// Keeping this for now but it should skip if already initialized
  Future<void> _initializeAndroidAuto() async {
    // Check if already initialized by main.dart
    if (AndroidAutoManager().isAndroidAutoActive) {
      debugPrint("✅ LibraryScreen: AndroidAutoManager already initialized by main.dart, skipping");
      _androidAutoInitialized = true;
      return;
    }
    
    debugPrint("🔵 LibraryScreen: _initializeAndroidAuto called (initialized=$_androidAutoInitialized, mounted=$mounted)");
    
    if (_androidAutoInitialized || !mounted) {
      debugPrint("⚠️ LibraryScreen: Skipping init - already initialized or not mounted");
      return;
    }
    
    try {
      debugPrint("📱 LibraryScreen: Starting Android Auto initialization (fallback)");
      final audiobookProvider = provider.Provider.of<AudiobookProvider>(context, listen: false);
      final audioService = SimpleAudioService();
      final storageService = StorageService();
      
      debugPrint("📱 LibraryScreen: Calling AndroidAutoManager().initialize()");
      await AndroidAutoManager().initialize(
        audiobookProvider: audiobookProvider,
        audioService: audioService,
        storageService: storageService,
      );
      
      _androidAutoInitialized = true;
      debugPrint("✅ LibraryScreen: Android Auto fully initialized with providers");
      
      // Force an immediate sync after initialization
      debugPrint("🔄 LibraryScreen: Forcing immediate data sync");
      await AndroidAutoManager().forceSyncNow();
      debugPrint("✅ LibraryScreen: Immediate sync completed");
    } catch (e) {
      debugPrint("❌ LibraryScreen: Error initializing Android Auto: $e");
      debugPrint("Stack trace: ${StackTrace.current}");
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When app comes to foreground, refresh the library
    if (state == AppLifecycleState.resumed) {
      _refreshLibrary();
      _animationController.reset();
      _animationController.forward();
    }
  }

  // Refresh the library without a full reload
  void _refreshLibrary() {
    if (mounted) {
      final audiobookProvider = provider.Provider.of<AudiobookProvider>(context, listen: false);
      audiobookProvider.refreshUI();
      setState(() {});
    }
  }

  // Function to check for and load last played position
  Future<void> _loadLastPositionAndNavigate(
    BuildContext context,
    Audiobook audiobook,
  ) async {
    // Check mounted state BEFORE async gap
    if (!context.mounted) return;

    final storageService = StorageService();
    final lastPositionData = await storageService.loadLastPosition(
      audiobook.id,
    );

    // Check mounted state AFTER async gap
    if (!context.mounted) return;

    // Get the provider to record that this book was played
    final audiobookProvider = provider.Provider.of<AudiobookProvider>(context, listen: false);

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

    // When returning from player screen, force refresh the library to update progress
    if (context.mounted) {
      final audiobookProvider = provider.Provider.of<AudiobookProvider>(context, listen: false);
      // Notify listeners to trigger UI update without a full reload
      audiobookProvider.refreshUI();

      // Force update all AudiobookTile widgets
      setState(() {});
    }
  }

  // Show the edit title dialog
  Future<void> _showEditTitleDialog(
    BuildContext context,
    Audiobook audiobook,
    AudiobookProvider provider,
  ) async {
    final currentTitle = provider.getTitleForAudiobook(audiobook);
    final TextEditingController controller = TextEditingController(
      text: currentTitle,
    );

    final result = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Edit Title'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Audiobook Title',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              textCapitalization: TextCapitalization.words,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('Save'),
              ),
            ],
          ),
    );

    if (result != null) {
      await provider.setCustomTitle(audiobook.id, result);
    }
  }

  // Show the delete confirmation dialog
  Future<void> _showDeleteConfirmationDialog(
    BuildContext context,
    Audiobook audiobook,
    AudiobookProvider provider,
  ) async {
    final title = provider.getTitleForAudiobook(audiobook);

    final result = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Remove Audiobook'),
            content: Text(
              'Are you sure you want to remove "$title" from your library?\n\n'
              'This will not delete the files from your device, only remove it from the app.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.errorContainer,
                  foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
                ),
                child: const Text('Remove'),
              ),
            ],
          ),
    );

    if (result == true) {
      try {
        await provider.removeAudiobook(audiobook.id, ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed "$title" from library'),
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
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error removing "$title": $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          );
        }
      }
    }
  }

  // Show the long-press actions menu
  void _showLongPressMenu(
    BuildContext context,
    Audiobook audiobook,
    AudiobookProvider provider,
  ) {
    final title = provider.getTitleForAudiobook(audiobook);
    final colorScheme = Theme.of(context).colorScheme;
    
    // Get tag information for this book
    final audiobookTags = ref.watch(audiobookTagsProvider);
    final bookTags = audiobookTags[audiobook.id] ?? <String>{};
    final isFavorited = bookTags.contains('Favorites');



    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Manage "$title"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Favorites toggle
            ListTile(
              leading: Icon(
                isFavorited ? Icons.favorite : Icons.favorite_border,
                color: isFavorited ? const Color(0xFFB71C1C) : colorScheme.onSurfaceVariant, // Deep red for favorites
              ),
              title: Text(isFavorited ? 'Remove from Favorites' : 'Add to Favorites'),
              onTap: () {
                Navigator.pop(context);
                _toggleFavorite(audiobook.id);
              },
            ),
            
            // Manage tags
            ListTile(
              leading: Stack(
                children: [
                  Icon(
                    Icons.label_outline,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  if (bookTags.length > 1 || (bookTags.length == 1 && !isFavorited))
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 12,
                          minHeight: 12,
                        ),
                        child: Text(
                          '${bookTags.length - (isFavorited ? 1 : 0)}',
                          style: TextStyle(
                            color: colorScheme.onPrimary,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              title: const Text('Manage Tags'),
              subtitle: bookTags.isEmpty 
                  ? const Text('No tags assigned')
                  : Text('${bookTags.length - (isFavorited ? 1 : 0)} custom tags'),
              onTap: () {
                Navigator.pop(context);
                _showTagAssignmentDialog(context, audiobook, title);
              },
            ),
            
            const Divider(),
            
            ListTile(
              leading: Icon(
                Icons.edit_rounded,
                color: colorScheme.primary,
              ),
              title: const Text('Edit Title'),
              onTap: () {
                Navigator.pop(context);
                _showEditTitleDialog(context, audiobook, provider);
              },
            ),
            
            const Divider(),
            
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: colorScheme.error,
              ),
              title: const Text('Remove from Library'),
              subtitle: const Text(
                'Files will not be deleted from your device',
              ),
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirmationDialog(
                  context,
                  audiobook,
                  provider,
                );
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

  // Toggle favorite status for an audiobook
  void _toggleFavorite(String audiobookId) {
    ref.read(audiobookTagsProvider.notifier).toggleFavorite(audiobookId);
    
    // Update tag usage
    ref.read(tagProvider.notifier).updateTagUsage('Favorites');
  }

  // Show tag assignment dialog
  void _showTagAssignmentDialog(BuildContext context, Audiobook audiobook, String customTitle) {
    showDialog(
      context: context,
      builder: (context) => TagAssignmentDialog(
        audiobook: audiobook,
        customTitle: customTitle,
      ),
    );
  }

  // Show dialog to add single or multiple audiobooks or scan existing library
  void _showAddBooksDialog(BuildContext context, AudiobookProvider provider) {
    // Clear any previous error messages when opening the dialog
    provider.clearErrorMessage();
    
    final colorScheme = Theme.of(context).colorScheme;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Library Actions',
          style: TextStyle(
            color: colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.book, color: colorScheme.primary),
              title: const Text('Add Single Book'),
              subtitle: const Text('Select a single folder containing audio files'),
              onTap: () async {
                Navigator.pop(context);
                await provider.addAudiobookFolder();
                await _handleAutoTagCreation(provider);
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.auto_stories, color: colorScheme.primary),
              title: const Text('Scan for Books'),
              subtitle: const Text('Recursively scan for audiobooks in any folder structure'),
              onTap: () async {
                Navigator.pop(context);
                await provider.addAudiobooksRecursively();
                await _handleAutoTagCreation(provider);
              },
            ),
            // Add the new scan existing library option
            if (provider.audiobooks.isNotEmpty) ...[
              const Divider(),
              ListTile(
                leading: Icon(Icons.local_offer_outlined, color: colorScheme.secondary),
                title: const Text('Scan Library for Tags'),
                subtitle: const Text('Create tags from existing books\' folder structure'),
                onTap: () async {
                  Navigator.pop(context);
                  await _scanExistingLibraryForTags(provider);
                },
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Clear error state when canceling
              provider.clearErrorMessage();
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
        ],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  // Handle scanning existing library for auto-tags
  Future<void> _scanExistingLibraryForTags(AudiobookProvider provider) async {
    try {
      // Show loading indicator
      if (mounted) {
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
                const Text('Scanning library for tags...'),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // Perform the scan
      await provider.scanExistingLibraryForTags(ref);

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: Theme.of(context).colorScheme.onInverseSurface,
                  size: 16,
                ),
                const SizedBox(width: 12),
                const Text('Library scan completed! Tags created from folder structure.'),
              ],
            ),
            backgroundColor: Theme.of(context).colorScheme.inverseSurface,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'View Tags',
              textColor: Theme.of(context).colorScheme.primary,
              onPressed: () {
                // Switch to tags view
                ref.read(libraryModeProvider.notifier).updateLibraryMode(LibraryMode.tags);
              },
            ),
          ),
        );
      }

    } catch (e) {
      debugPrint("Error scanning existing library for tags: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.onError,
                  size: 16,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Error scanning library: ${e.toString()}'),
                ),
              ],
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // Handle auto-tag creation after audiobooks are added
  Future<void> _handleAutoTagCreation(AudiobookProvider provider) async {
    try {
      // Check if there are newly added books ready for auto-tagging
      final rootPath = provider.lastScannedRootPath;
      final addedPaths = provider.lastAddedPaths;
      
      debugPrint("=== AUTO-TAG CREATION DEBUG ===");
      debugPrint("Root path: $rootPath");
      debugPrint("Added paths: $addedPaths");
      debugPrint("Added paths length: ${addedPaths?.length ?? 0}");
      
      if (rootPath != null && addedPaths != null && addedPaths.isNotEmpty) {
        debugPrint("Creating auto-tags for ${addedPaths.length} newly added audiobooks");
        debugPrint("Root path for auto-tagging: $rootPath");
        debugPrint("Books to process: ${addedPaths.map((path) => path.split('/').last).join(', ')}");
        
        // Show loading indicator (optional - could be a SnackBar)
        if (mounted) {
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
                  const Text('Creating auto-tags...'),
                ],
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        
        // CRITICAL FIX: Create auto-tags based on number of books
        if (addedPaths.length == 1) {
          debugPrint("Processing single book auto-tags");
          await provider.createAutoTagsForSingleBook(
            addedPaths.first,
            rootPath,
            ref,
          );
        } else {
          debugPrint("Processing multiple books auto-tags");
          await provider.createAutoTagsForMultipleBooks(
            addedPaths,
            rootPath,
            ref,
          );
        }
        
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    Icons.local_offer_rounded,
                    color: Theme.of(context).colorScheme.onInverseSurface,
                    size: 16,
                  ),
                  const SizedBox(width: 12),
                  const Text('Auto-tags created from folder structure'),
                ],
              ),
              backgroundColor: Theme.of(context).colorScheme.inverseSurface,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        
      } else {
        debugPrint("No books available for auto-tagging");
        debugPrint("  rootPath is null: ${rootPath == null}");
        debugPrint("  addedPaths is null: ${addedPaths == null}");
        debugPrint("  addedPaths is empty: ${addedPaths?.isEmpty ?? true}");
      }
    } catch (e) {
      debugPrint("Error in auto-tag creation: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating auto-tags: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use watch for automatic rebuilds when provider notifies listeners
    final provider = context.watch<AudiobookProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final seedColor = themeProvider.seedColor;

    // Check for landscape orientation
    final isLandscape = ResponsiveUtils.isLandscape(context);

    return Scaffold(
      body: Stack(
        children: [
          // Main app content
          NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              floating: true, 
              snap: true,
              pinned: true, // Keep the app bar visible and pinned at the top
              backgroundColor: colorScheme.surfaceContainerLow.withOpacity(0.95),
              expandedHeight: 80,
              systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: colorScheme.brightness == Brightness.dark
                    ? Brightness.light
                    : Brightness.dark,
              ),
              title: Row(
                children: [
                  SizedBox(
                    width: 38,
                    height: 38,
                    child: const AppLogo(size: 38, showTitle: false),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        "Widdle Reader",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: seedColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                    // Search button
                    Consumer(
                      builder: (context, widgetRef, child) {
                        final searchState = ref.watch(searchProvider);
                        return IconButton(
                          icon: Icon(
                            searchState.isActive ? Icons.search_off_rounded : Icons.search_rounded,
                            size: 24,
                          ),
                          tooltip: searchState.isActive ? 'Close Search' : 'Search Library',
                          onPressed: () {
                            ref.read(searchProvider.notifier).toggleSearch();
                          },
                        );
                      },
                    ),
                    
                // Sleep Timer button
                IconButton(
                  icon: CountdownTimerWidget(
                    size: 24.0,
                    showIcon: true,
                    onTap: null,
                  ),
                  tooltip: 'Sleep Timer',
                  onPressed: _showSleepTimerDialog,
                ),
                
                // Settings button
                IconButton(
                  icon: const Icon(
                    Icons.settings_outlined,
                    size: 24,
                  ),
                  tooltip: "Settings",
                  onPressed: () async {
                    await Navigator.pushNamed(context, '/settings');
                    // Refresh when returning from settings
                    _refreshLibrary();
                  },
                ),
                const SizedBox(width: 8),
              ],
            ),
          ];
        },
        body: Container(
          decoration: AppTheme.gradientBackground(context),
          child: Column(
            children: [
                  // Search bar (only show when search is active)
                  Consumer(
                    builder: (context, widgetRef, child) {
                      final searchState = ref.watch(searchProvider);
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: searchState.isActive
                            ? const SearchBarWidget()
                            : const SizedBox.shrink(),
                      );
                    },
                  ),
                  
                  // Toggle bar between Library and Tags (only show when search is not active)
                  Consumer(
                    builder: (context, widgetRef, child) {
                      final searchState = ref.watch(searchProvider);
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: searchState.isActive
                            ? const SizedBox.shrink()
                            : const LibraryToggle(),
                      );
                    },
                  ),
              
              // Main content area
              Expanded(
                child: Stack(
                  children: [
                    // Main content with conditional view based on selected mode
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: Column(
                        children: [
                          // Loading card at the top (only in library mode when not searching)
                          Consumer(
                            builder: (context, widgetRef, child) {
                              final libraryMode = ref.watch(libraryModeProvider);
                              final searchState = ref.watch(searchProvider);
                              
                              // Only show loading card in library mode when not searching
                              if (libraryMode == LibraryMode.library && !searchState.isActive) {
                                return const DetailedLoadingWidget();
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                          
                          // Main content below loading card
                          Expanded(
                            child: Consumer(
                              builder: (context, widgetRef, child) {
                                final libraryMode = ref.watch(libraryModeProvider);
                                    final searchState = ref.watch(searchProvider);
                                    
                                    // If search is active, show search results
                                    if (searchState.isActive) {
                                      return _buildSearchResults(context, provider, searchState, colorScheme);
                                    }
                                
                                if (libraryMode == LibraryMode.tags) {
                                  return const TagsView();
                                } else {
                                      // Library mode - show audiobooks with sorting
                                      return Consumer(
                                        builder: (context, widgetRef, child) {
                                          final sortOption = ref.watch(librarySortOptionProvider);
                                          
                                          // Apply sorting (optimized to skip if sort option hasn't changed)
                                          provider.sortAudiobooks(sortOption);
                                          
                                  return provider.audiobooks.isEmpty && !provider.isLoading
                                      ? _buildEmptyLibraryView(context, provider, colorScheme)
                                      : isLandscape
                                          ? _buildGridView(context, provider)
                                          : _buildListView(context, provider);
                                        },
                                      );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Error/Info Message
                    if (provider.errorMessage != null && !provider.isLoading)
                      _buildErrorMessage(context, provider),
                      
                        // No loading overlays - seamless experience
                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ],
                ),
      
      // Floating action button (only show in Library mode)
      floatingActionButton: Consumer(
        builder: (context, widgetRef, child) {
          final libraryMode = ref.watch(libraryModeProvider);
          final showFab = libraryMode == LibraryMode.library && !provider.isLoading;
          
          return AnimatedScale(
            scale: showFab ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: FloatingActionButton.extended(
              onPressed: provider.isLoading
                  ? null
                  : () => _showAddBooksDialog(context, provider),
              elevation: 3,
              label: const Text('Add Books'),
              icon: const Icon(Icons.add_rounded),
              tooltip: 'Add Audiobooks',
            ),
          );
        },
      ),
    );
  }

  // Empty library view
  Widget _buildEmptyLibraryView(BuildContext context, AudiobookProvider audiobookProvider, ColorScheme colorScheme) {
    if (audiobookProvider.errorMessage != null || audiobookProvider.permissionPermanentlyDenied) {
      return const SizedBox.shrink(); // Error handled by overlay
    }
    
    final themeProvider = provider.Provider.of<ThemeProvider>(context, listen: false);
    final seedColor = themeProvider.seedColor;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Empty library illustration
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.menu_book_outlined,
                size: 64,
                color: seedColor,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Your library is empty',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tap the + button to add an audiobook folder.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Grid view for landscape orientation
  Widget _buildGridView(BuildContext context, AudiobookProvider audiobookProvider) {
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
      itemCount: audiobookProvider.audiobooks.length,
      itemBuilder: (context, index) {
        final audiobook = audiobookProvider.audiobooks[index];
        
        // Apply staggered animation for items
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: 1.0,
          curve: Curves.easeOut,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 200),
            scale: 1.0,
            child: GestureDetector(
              onTap: () => _loadLastPositionAndNavigate(context, audiobook),
              onLongPress: () => _showLongPressMenu(context, audiobook, audiobookProvider),
              child: AudiobookTile(
                // Use a more comprehensive key that will force a rebuild when reset happens
                key: ValueKey(
                  '${audiobook.id}-${audiobookProvider.isCompletedBook(audiobook.id)}-${DateTime.now().millisecondsSinceEpoch}',
                ),
                audiobook: audiobook,
                customTitle: audiobookProvider.getTitleForAudiobook(audiobook),
              ),
            ),
          ),
        );
      },
    );
  }

  // List view for portrait orientation
  Widget _buildListView(BuildContext context, AudiobookProvider audiobookProvider) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      physics: const BouncingScrollPhysics(),
      itemCount: audiobookProvider.audiobooks.length,
      itemBuilder: (context, index) {
        final audiobook = audiobookProvider.audiobooks[index];
        
        // Apply staggered animation for items
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: 1.0,
          curve: Curves.easeOut,
          child: GestureDetector(
            onTap: () => _loadLastPositionAndNavigate(context, audiobook),
            onLongPress: () => _showLongPressMenu(context, audiobook, audiobookProvider),
            child: AudiobookTile(
              // Use a more comprehensive key that will force a rebuild when reset happens
              key: ValueKey(
                '${audiobook.id}-${audiobookProvider.isCompletedBook(audiobook.id)}-${DateTime.now().millisecondsSinceEpoch}',
              ),
              audiobook: audiobook,
              customTitle: audiobookProvider.getTitleForAudiobook(audiobook),
            ),
          ),
        );
      },
    );
  }

  // Build search results view
  Widget _buildSearchResults(BuildContext context, AudiobookProvider audiobookProvider, SearchState searchState, ColorScheme colorScheme) {
    // Get search results
    final results = _getSearchResults(audiobookProvider, searchState.query);
    
    if (searchState.query.trim().isEmpty) {
      // Show empty search state
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_rounded,
                size: 64,
                color: colorScheme.onSurfaceVariant.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'Start typing to search',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Search for books, authors, or tags',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Build search result tiles
    final searchResultTiles = results.map((audiobook) {
      return GestureDetector(
        onTap: () => _loadLastPositionAndNavigate(context, audiobook),
        onLongPress: () => _showLongPressMenu(context, audiobook, audiobookProvider),
        child: AudiobookTile(
          key: ValueKey('search_${audiobook.id}'),
          audiobook: audiobook,
          customTitle: audiobookProvider.getTitleForAudiobook(audiobook),
        ),
      );
    }).toList();

    return SearchResultsWidget(
      children: searchResultTiles,
      query: searchState.query,
    );
  }

  // Get search results using the search service
  List<Audiobook> _getSearchResults(AudiobookProvider audiobookProvider, String query) {
    if (query.trim().isEmpty) {
      return [];
    }

    // Get all necessary data for search
    final audiobooks = audiobookProvider.audiobooks;
    final customTitles = audiobookProvider.customTitles;
    
    // Get audiobook tags
    final Map<String, Set<String>> audiobookTags = {};
    try {
      final tagState = ref.read(audiobookTagsProvider);
      audiobookTags.addAll(tagState);
    } catch (e) {
      // Handle case where tags provider is not available
      debugPrint('Could not load tags for search: $e');
    }
    
    // Get all tags
    final List<Tag> allTags = [];
    try {
      final tagsAsyncValue = ref.read(syncedTagProvider);
      tagsAsyncValue.whenData((tags) => allTags.addAll(tags));
    } catch (e) {
      // Handle case where tags provider is not available
      debugPrint('Could not load tag list for search: $e');
    }

    return SearchService.searchAudiobooks(
      audiobooks: audiobooks,
      query: query,
      customTitles: customTitles,
      audiobookTags: audiobookTags,
      allTags: allTags,
    );
  }

  // Extracted error message widget
  Widget _buildErrorMessage(BuildContext context, AudiobookProvider audiobookProvider) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLandscape = ResponsiveUtils.isLandscape(context);

    return Positioned(
      bottom: 100, // Position above FAB
      left: isLandscape ? 100 : 20, // Wider margins in landscape
      right: isLandscape ? 100 : 20,
      child: Material(
        // Wrap with Material for elevation and shape
        elevation: 4,
        borderRadius: BorderRadius.circular(16),
        color:
            audiobookProvider.permissionPermanentlyDenied
                ? colorScheme.errorContainer
                : colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: colorScheme.onErrorContainer,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  audiobookProvider.errorMessage!,
                  style: TextStyle(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // Show settings button only if permission is permanently denied
              if (audiobookProvider.permissionPermanentlyDenied)
                TextButton(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.settings, color: colorScheme.primary, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        "Settings",
                        style: TextStyle(color: colorScheme.primary),
                      ),
                    ],
                  ),
                  onPressed: () => audiobookProvider.openSettings(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Show sleep timer dialog
  void _showSleepTimerDialog() {
    final timerProvider = provider.Provider.of<SleepTimerProvider>(context, listen: false);
    final colorScheme = Theme.of(context).colorScheme;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(
              'Sleep Timer',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (timerProvider.isActive)
                  StreamBuilder<Duration>(
                    stream: timerProvider.remainingTimeStream,
                    initialData: timerProvider.remainingTime,
                    builder: (context, snapshot) {
                      final remainingTime = snapshot.data ?? Duration.zero;
                      final minutes = remainingTime.inMinutes;
                      final seconds = remainingTime.inSeconds % 60;
                      final timeDisplay = '$minutes:${seconds.toString().padLeft(2, '0')}';
                      
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 50,
                              height: 50,
                              child: CircularProgressIndicator(
                                value: remainingTime.inSeconds / (timerProvider.totalDuration?.inSeconds ?? 1),
                                backgroundColor: colorScheme.surfaceVariant,
                                strokeWidth: 5,
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              timeDisplay,
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 24,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildTimerOption(5),
                    _buildTimerOption(15),
                    _buildTimerOption(30),
                    _buildTimerOption(45),
                    _buildTimerOption(60),
                    _buildCustomTimerOption(),
                  ],
                ),
                
                if (timerProvider.isActive)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: OutlinedButton.icon(
                      onPressed: () {
                        timerProvider.cancelTimer();
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Sleep timer canceled'),
                            duration: Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      icon: const Icon(Icons.timer_off),
                      label: const Text('Cancel Timer'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        }
      ),
    );
  }
  
  // Build timer option button
  Widget _buildTimerOption(int minutes) {
    final colorScheme = Theme.of(context).colorScheme;
    final timerProvider = provider.Provider.of<SleepTimerProvider>(context, listen: false);
    
    return ElevatedButton(
      onPressed: () {
        timerProvider.startTimer(Duration(minutes: minutes));
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sleep timer set for $minutes minutes'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Text('$minutes min'),
    );
  }
  
  // Build custom timer option
  Widget _buildCustomTimerOption() {
    final colorScheme = Theme.of(context).colorScheme;
    
    return ElevatedButton(
      onPressed: () {
        Navigator.of(context).pop();
        _showCustomTimerDialog();
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: const Text('Custom'),
    );
  }
  
  // Show custom timer dialog with number input
  void _showCustomTimerDialog() {
    final TextEditingController _minutesController = TextEditingController();
    final colorScheme = Theme.of(context).colorScheme;
    final timerProvider = provider.Provider.of<SleepTimerProvider>(context, listen: false);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Custom Timer'),
        content: TextField(
          controller: _minutesController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Minutes',
            hintText: 'Enter minutes',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final minutes = int.tryParse(_minutesController.text);
              if (minutes != null && minutes > 0) {
                timerProvider.startTimer(Duration(minutes: minutes));
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Sleep timer set for $minutes minutes'),
                    duration: const Duration(seconds: 3),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Start Timer'),
          ),
        ],
      ),
    );
  }
}
