import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

import '../providers/audiobook_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/audiobook_tile.dart';
import '../widgets/app_logo.dart';
import '../models/audiobook.dart';
import '../services/storage_service.dart';
import '../theme.dart';
import '../utils/responsive_utils.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  
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
      final provider = Provider.of<AudiobookProvider>(context, listen: false);
      provider.refreshUI();
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
    final provider = Provider.of<AudiobookProvider>(context, listen: false);

    // Record that this book is being played (will update timestamps and sort order)
    await provider.recordBookPlayed(audiobook.id);

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
      final provider = Provider.of<AudiobookProvider>(context, listen: false);
      // Notify listeners to trigger UI update without a full reload
      provider.refreshUI();

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
      await provider.removeAudiobook(audiobook.id);
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
    final isLandscape = context.isLandscape;

    // Adjust menu size and position based on orientation
    final double maxWidth =
        isLandscape
            ? MediaQuery.of(context).size.width * 0.6
            : MediaQuery.of(context).size.width * 0.9;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => Container(
            width: maxWidth,
            padding: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
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
            ),
          ),
    );
  }

  // Show dialog to add single or multiple audiobooks
  void _showAddBooksDialog(BuildContext context, AudiobookProvider provider) {
    // Clear any previous error messages when opening the dialog
    provider.clearErrorMessage();
    
    final colorScheme = Theme.of(context).colorScheme;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Add Audiobooks',
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
              subtitle: const Text('Select a folder containing one audiobook'),
              onTap: () {
                Navigator.pop(context);
                provider.addAudiobookFolder();
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.library_add, color: colorScheme.primary),
              title: const Text('Add Multiple Books'),
              subtitle: const Text('Select a root folder with multiple audiobook subfolders'),
              onTap: () {
                Navigator.pop(context);
                provider.addMultipleAudiobooks();
              },
            ),
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
      body: NestedScrollView(
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
                  Text(
                    "Widdle Reader",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: seedColor,
                    ),
                  ),
                ],
              ),
              actions: [
                // Refresh button
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child:
                      provider.isLoading
                          ? Container(
                            margin: const EdgeInsets.all(8),
                            width: 40,
                            height: 40,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: seedColor,
                            ),
                          )
                          : IconButton(
                            icon: const Icon(
                              Icons.refresh_rounded,
                              size: 24,
                            ),
                            tooltip: "Refresh Library",
                            onPressed: () => provider.loadAudiobooks(),
                          ),
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
          child: Stack(
            children: [
              // Main content with fade-in animation
              FadeTransition(
                opacity: _fadeAnimation,
                child: provider.audiobooks.isEmpty && !provider.isLoading
                    ? _buildEmptyLibraryView(context, provider, colorScheme)
                    : isLandscape
                        ? _buildGridView(context, provider)
                        : _buildListView(context, provider),
              ),
              
              // Error/Info Message
              if (provider.errorMessage != null && !provider.isLoading)
                _buildErrorMessage(context, provider),
                
              // Loading overlay
              if (provider.isLoading)
                Container(
                  color: Colors.black.withOpacity(0.3),
                  child: Center(
                    child: Card(
                      elevation: 6,
                      shadowColor: colorScheme.shadow.withOpacity(0.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 48,
                              height: 48,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              "Loading Library...",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      // Floating action button
      floatingActionButton: AnimatedScale(
        scale: provider.isLoading ? 0.0 : 1.0,
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
      ),
    );
  }

  // Empty library view
  Widget _buildEmptyLibraryView(BuildContext context, AudiobookProvider provider, ColorScheme colorScheme) {
    if (provider.errorMessage != null || provider.permissionPermanentlyDenied) {
      return const SizedBox.shrink(); // Error handled by overlay
    }
    
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
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
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => _showAddBooksDialog(context, provider),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Books'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Grid view for landscape orientation
  Widget _buildGridView(BuildContext context, AudiobookProvider provider) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Calculate how many items to show per row based on screen width
    final crossAxisCount = screenWidth > 1200 ? 4 : (screenWidth > 800 ? 3 : 2);

    return GridView.builder(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 1.8,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: provider.audiobooks.length,
      itemBuilder: (context, index) {
        final audiobook = provider.audiobooks[index];
        
        // Apply staggered animation for items
        return AnimatedOpacity(
          duration: Duration(milliseconds: 300),
          opacity: 1.0,
          curve: Curves.easeOut,
          child: AnimatedScale(
            duration: Duration(milliseconds: 200),
            scale: 1.0,
            child: GestureDetector(
              onTap: () => _loadLastPositionAndNavigate(context, audiobook),
              onLongPress: () => _showLongPressMenu(context, audiobook, provider),
              child: AudiobookTile(
                // Use a more comprehensive key that will force a rebuild when reset happens
                key: ValueKey(
                  '${audiobook.id}-${provider.isCompletedBook(audiobook.id)}-${DateTime.now().millisecondsSinceEpoch}',
                ),
                audiobook: audiobook,
                customTitle: provider.getTitleForAudiobook(audiobook),
              ),
            ),
          ),
        );
      },
    );
  }

  // List view for portrait orientation
  Widget _buildListView(BuildContext context, AudiobookProvider provider) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      physics: const BouncingScrollPhysics(),
      itemCount: provider.audiobooks.length,
      itemBuilder: (context, index) {
        final audiobook = provider.audiobooks[index];
        
        // Apply staggered animation for items
        return AnimatedOpacity(
          duration: Duration(milliseconds: 300),
          opacity: 1.0,
          curve: Curves.easeOut,
          child: GestureDetector(
            onTap: () => _loadLastPositionAndNavigate(context, audiobook),
            onLongPress: () => _showLongPressMenu(context, audiobook, provider),
            child: AudiobookTile(
              // Use a more comprehensive key that will force a rebuild when reset happens
              key: ValueKey(
                '${audiobook.id}-${provider.isCompletedBook(audiobook.id)}-${DateTime.now().millisecondsSinceEpoch}',
              ),
              audiobook: audiobook,
              customTitle: provider.getTitleForAudiobook(audiobook),
            ),
          ),
        );
      },
    );
  }

  // Extracted error message widget
  Widget _buildErrorMessage(BuildContext context, AudiobookProvider provider) {
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
            provider.permissionPermanentlyDenied
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
                  provider.errorMessage!,
                  style: TextStyle(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // Show settings button only if permission is permanently denied
              if (provider.permissionPermanentlyDenied)
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
                  onPressed: () => provider.openSettings(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
