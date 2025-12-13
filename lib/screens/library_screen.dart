import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode
import 'package:widdle_reader/screens/review_editor_screen.dart'; // Import ReviewEditorScreen
import 'package:widdle_reader/screens/reviews_list_screen.dart'; // Import ReviewsListScreen
import 'package:provider/provider.dart' as provider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'settings_screen.dart';
import 'simple_player_screen.dart';



import '../providers/audiobook_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/sleep_timer_provider.dart';
import '../providers/tag_provider.dart';
import '../providers/search_provider.dart';
import '../widgets/audiobook_tile.dart';
import '../widgets/app_logo.dart';
import '../widgets/countdown_timer_widget.dart';
import '../widgets/tags_view.dart';
import '../widgets/tag_assignment_dialog.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/detailed_loading_widget.dart';
import '../widgets/mini_player_widget.dart';
import '../widgets/xp_badge.dart';
import '../models/audiobook.dart';
import '../models/tag.dart';
import '../services/storage_service.dart';
import '../services/simple_audio_service.dart';
import '../services/android_auto_manager.dart';
import '../theme.dart';
import '../utils/responsive_utils.dart';
import '../utils/helpers.dart';

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
  int _selectedIndex = 0; // 0 = Library, 1 = Completed, 2 = Tags
  
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

  // Modern bottom sheet implementation for long-press menu
  void _showLongPressMenu(
    BuildContext context,
    Audiobook audiobook,
    AudiobookProvider provider,
  ) {
    final title = provider.getTitleForAudiobook(audiobook);
    final colorScheme = Theme.of(context).colorScheme;
    
    // Get tag information
    final audiobookTags = ref.watch(audiobookTagsProvider);
    final bookTags = audiobookTags[audiobook.id] ?? <String>{};
    final isFavorited = bookTags.contains('Favorites');
    final isCompleted = provider.isCompletedBook(audiobook.id);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with Cover Art
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Row(
                    children: [
                      // Cover Art
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: buildCoverWidget(
                          context,
                          audiobook,
                          size: 60,
                          customTitle: title,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Title and Author
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (audiobook.author != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                audiobook.author!,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(indent: 24, endIndent: 24),
                
                // Actions List
                // 1. Write Review
                ListTile(
                  leading: Icon(Icons.rate_review_outlined, color: colorScheme.onSurfaceVariant),
                  title: const Text('Write Review'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ReviewEditorScreen(audiobook: audiobook),
                      ),
                    );
                  },
                ),
                
                // 2. Edit Title
                 ListTile(
                  leading: Icon(Icons.edit_outlined, color: colorScheme.onSurfaceVariant),
                  title: const Text('Edit Title'),
                  onTap: () {
                    Navigator.pop(context);
                    _showEditTitleDialog(context, audiobook, provider);
                  },
                ),
                
                // 3. Edit Tags
                ListTile(
                  leading: Icon(Icons.label_outline, color: colorScheme.onSurfaceVariant),
                  title: const Text('Edit Tags'),
                  onTap: () {
                    Navigator.pop(context);
                    // Pass specific audiobook using the dialog
                    showDialog(
                      context: context,
                      builder: (context) => TagAssignmentDialog(
                        audiobook: audiobook,
                        customTitle: title,
                      ),
                    );
                  },
                ),
                
                // 4. Toggle Favorite
                ListTile(
                   leading: Icon(
                      isFavorited ? Icons.favorite : Icons.favorite_border, 
                      color: isFavorited ? Colors.red : colorScheme.onSurfaceVariant
                   ),
                   title: Text(isFavorited ? 'Remove from Favorites' : 'Add to Favorites'),
                   onTap: () {
                     _toggleFavorite(audiobook.id);
                     Navigator.pop(context);
                   },
                 ),
                 
                 // 5. Toggle Complete
                 ListTile(
                   leading: Icon(
                      isCompleted ? Icons.check_circle : Icons.check_circle_outline,
                      color: isCompleted ? Colors.green : colorScheme.onSurfaceVariant,
                   ),
                   title: Text(isCompleted ? 'Mark as Unfinished' : 'Mark as Finished'),
                   onTap: () {
                      provider.toggleCompletionStatus(audiobook.id);
                      Navigator.pop(context);
                   },
                 ),

                const Divider(indent: 24, endIndent: 24),
                
                // 6. Delete (Destructive)
                ListTile(
                  leading: Icon(Icons.delete_outline, color: colorScheme.error),
                  title: Text(
                    'Remove from Library',
                    style: TextStyle(color: colorScheme.error),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteConfirmationDialog(context, audiobook, provider);
                  },
                ),
              ],
            ),
          ),
        );
      },
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
                leading: Icon(Icons.local_offer, color: colorScheme.secondary),
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
                
                // Statistics button
                IconButton(
                  icon: const Icon(
                    Icons.bar_chart_rounded,
                    size: 24,
                  ),
                  tooltip: 'Statistics',
                  onPressed: () {
                    Navigator.pushNamed(context, '/statistics');
                  },
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
              // Main content area
              Expanded(
                child: Stack(
                  children: [
                    // Main content with conditional view based on selected tab
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: Column(
                        children: [
                          // Search bar and controls (only show in Library and Completed tabs)
                          if (_selectedIndex == 0 || _selectedIndex == 1)
                            _buildSearchAndSortBar(context, ref),
                          
                          // Loading card at the top (only in library mode when not searching)
                          Consumer(
                            builder: (context, widgetRef, child) {
                              final searchState = ref.watch(searchProvider);
                              
                              // Only show loading card in library tab when not searching
                              if (_selectedIndex == 0 && !searchState.isActive) {
                                return const DetailedLoadingWidget();
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                          
                          // Main content below loading card
                          Expanded(
                            child: Consumer(
                              builder: (context, widgetRef, child) {
                                final searchState = ref.watch(searchProvider);
                                
                                // Switch content based on selected tab
                                if (_selectedIndex == 3) {
                                  // Reviews Hub
                                  return const ReviewsListScreen();
                                } else if (_selectedIndex == 2) {
                                  // Tags view
                                  return const TagsView();
                                } else if (_selectedIndex == 1) {
                                  // Completed books view
                                  return Consumer(
                                    builder: (context, widgetRef, child) {
                                      final sortOption = ref.watch(librarySortOptionProvider);
                                      
                                      // Apply sorting
                                      provider.sortAudiobooks(sortOption);
                                      
                                      var completedBooks = provider.completedBooksOnly;
                                      
                                      // Apply search filter if active
                                      if (searchState.query.isNotEmpty) {
                                        completedBooks = _getSearchResults(provider, searchState.query, booksToSearch: completedBooks);
                                      }
                                      
                                      return completedBooks.isEmpty && !provider.isLoading
                                          ? (searchState.query.isNotEmpty 
                                              ? _buildEmptySearchResults(context, colorScheme) 
                                              : _buildEmptyCompletedView(context, colorScheme))
                                          : (isLandscape || themeProvider.isGridView)
                                              ? _buildGridView(context, provider, isPortraitGrid: !isLandscape, booksToShow: completedBooks)
                                              : _buildListView(context, provider, booksToShow: completedBooks);
                                    },
                                  );
                                } else {
                                  // Library mode (ongoing books only)
                                  return Consumer(
                                    builder: (context, widgetRef, child) {
                                      final sortOption = ref.watch(librarySortOptionProvider);
                                      
                                      // Apply sorting
                                      provider.sortAudiobooks(sortOption);
                                      
                                      var ongoingBooks = provider.ongoingBooks;
                                      
                                      // Apply search filter if active
                                      if (searchState.query.isNotEmpty) {
                                        ongoingBooks = _getSearchResults(provider, searchState.query, booksToSearch: ongoingBooks);
                                      }
                                      
                                      return ongoingBooks.isEmpty && !provider.isLoading
                                          ? (searchState.query.isNotEmpty 
                                              ? _buildEmptySearchResults(context, colorScheme) 
                                              : _buildEmptyLibraryView(context, provider, colorScheme))
                                          : (isLandscape || themeProvider.isGridView)
                                              ? _buildGridView(context, provider, isPortraitGrid: !isLandscape, booksToShow: ongoingBooks)
                                              : _buildListView(context, provider, booksToShow: ongoingBooks);
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



          
          // Mini Player - appears at bottom when audiobook is playing
          // Note: This is now part of bottomNavigationBar
        ],
      ),
      
      // Floating action button (only show in Library tab)
      floatingActionButton: _selectedIndex == 0 && !provider.isLoading
          ? FloatingActionButton(
              onPressed: () => _showAddBooksDialog(context, provider),
              elevation: 3,
              child: const Icon(Icons.add_rounded),
              tooltip: 'Add Audiobooks',
            )
          : null,
      
      // Bottom Navigation Bar with Mini Player
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mini Player appears above navigation bar when playing
          const MiniPlayerWidget(),
          
          // Navigation Bar
          NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.auto_stories_outlined),
                selectedIcon: Icon(Icons.auto_stories),
                label: 'Library',
              ),
              NavigationDestination(
                icon: Icon(Icons.check_circle_outline),
                selectedIcon: Icon(Icons.check_circle),
                label: 'Completed',
              ),
              NavigationDestination(
                icon: Icon(Icons.local_offer_outlined),
                selectedIcon: Icon(Icons.local_offer),
                label: 'Tags',
              ),
              NavigationDestination(
                icon: Icon(Icons.rate_review_outlined),
                selectedIcon: Icon(Icons.rate_review),
                label: 'Reviews',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Search bar and sort button
  Widget _buildSearchAndSortBar(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final searchState = ref.watch(searchProvider);
    final currentSort = ref.watch(librarySortOptionProvider);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Search bar
          Expanded(
            child: TextField(
              onTapOutside: (event) {
                FocusManager.instance.primaryFocus?.unfocus();
              },
              onChanged: (value) {
                ref.read(searchProvider.notifier).updateQuery(value);
                // We don't need to toggle active state anymore as we filter in-place
              },
              decoration: InputDecoration(
                hintText: 'Search audiobooks...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: searchState.isActive && searchState.query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          ref.read(searchProvider.notifier).updateQuery('');
                          FocusManager.instance.primaryFocus?.unfocus();
                        },
                      )
                    : null,
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Sort button
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _showLibrarySortMenu(context, ref, colorScheme),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    Icons.sort_rounded,
                    size: 24,
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

  // Show library sort menu
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

  // Get icon for library sort options
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

  // Empty search results view
  Widget _buildEmptySearchResults(BuildContext context, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: colorScheme.onSurfaceVariant.withOpacity(0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'No matches found',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search terms',
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

  // Empty completed view
  Widget _buildEmptyCompletedView(BuildContext context, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'No completed books yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Finished audiobooks will appear here',
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

  // Grid view for landscape or when grid view is enabled
  Widget _buildGridView(BuildContext context, AudiobookProvider audiobookProvider, {bool isPortraitGrid = false, List<Audiobook>? booksToShow}) {
  final screenWidth = MediaQuery.of(context).size.width;
  final books = booksToShow ?? audiobookProvider.audiobooks;
  
  // Calculate columns based on mode
  int crossAxisCount;
  double childAspectRatio;
  
  if (isPortraitGrid) {
    // Portrait Grid Mode
    crossAxisCount = screenWidth > 600 ? 3 : 2;
    childAspectRatio = 0.65; // Taller cards to prevent overflow with 2-line titles
  } else {
    // Landscape Mode (existing logic)
    crossAxisCount = screenWidth > 1200 ? 4 : (screenWidth > 800 ? 3 : 2);
    childAspectRatio = 1.8; // Wider cards for landscape
  }

  return GridView.builder(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    physics: const BouncingScrollPhysics(),
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: crossAxisCount,
      childAspectRatio: childAspectRatio,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
    ),
    itemCount: books.length,
    itemBuilder: (context, index) {
      final audiobook = books[index];
      
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
              isGridView: isPortraitGrid, // Enable grid layout for portrait grid
            ),
          ),
        ),
      );
    },
  );
}

  // List view for portrait orientation
  Widget _buildListView(BuildContext context, AudiobookProvider audiobookProvider, {List<Audiobook>? booksToShow}) {
    final books = booksToShow ?? audiobookProvider.audiobooks;
    
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      physics: const BouncingScrollPhysics(),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final audiobook = books[index];
        
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

  // Get search results using the search service
  List<Audiobook> _getSearchResults(AudiobookProvider audiobookProvider, String query, {List<Audiobook>? booksToSearch}) {
    // Get all necessary data for search
    final audiobooks = booksToSearch ?? audiobookProvider.audiobooks;
    
    if (query.trim().isEmpty) {
      return audiobooks;
    }
    
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
