import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/audiobook_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/audiobook_tile.dart';
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
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // Register to detect when app becomes active
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When app comes to foreground, refresh the library
    if (state == AppLifecycleState.resumed) {
      _refreshLibrary();
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

    // Use pushNamed and then refresh the UI when returning
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
              ElevatedButton(
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
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
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
          ),
        );
      }
    }
  }

  // Show the reset progress confirmation dialog
  Future<void> _showResetProgressDialog(
    BuildContext context,
    Audiobook audiobook,
  ) async {
    final title = Provider.of<AudiobookProvider>(
      context,
      listen: false,
    ).getTitleForAudiobook(audiobook);

    final result = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Reset Progress'),
            content: Text(
              'Are you sure you want to reset your listening progress for "$title"?\n\n'
              'This will mark the book as unread and remove your last position.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
                child: const Text('Reset'),
              ),
            ],
          ),
    );

    if (result == true && context.mounted) {
      await _resetAudiobookProgress(context, audiobook);
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
          (context) => Center(
            child: Container(
              width: maxWidth,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 24),
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
                    ListTile(
                      leading: Icon(
                        Icons.restart_alt_rounded,
                        color: colorScheme.secondary,
                      ),
                      title: const Text('Reset Progress'),
                      subtitle: const Text(
                        'Mark as unread and remove current position',
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _showResetProgressDialog(context, audiobook);
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
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  // Reset audiobook progress
  Future<void> _resetAudiobookProgress(
    BuildContext context,
    Audiobook audiobook,
  ) async {
    try {
      final storageService = StorageService();

      // Use the enhanced reset method that clears both position and cached progress
      await storageService.resetAudiobookProgress(audiobook.id);

      // Force refresh the library to update all tiles
      if (context.mounted) {
        final provider = Provider.of<AudiobookProvider>(context, listen: false);
        provider.refreshUI(); // Trigger UI refresh

        // Force update widgets
        setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Progress reset successfully'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            action: SnackBarAction(
              label: 'REFRESH',
              onPressed: () {
                provider.loadAudiobooks(); // Full reload if needed
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error resetting progress: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
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

    // Check for landscape orientation
    final isLandscape = ResponsiveUtils.isLandscape(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Widdle Reader',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            fontSize: 16,
          ),
        ),
        backgroundColor: colorScheme.surface.withOpacity(0.7),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.settings),
          ),
          tooltip: "Settings",
          onPressed: () async {
            await Navigator.pushNamed(context, '/settings');
            // Refresh when returning from settings
            _refreshLibrary();
          },
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
                        color: colorScheme.onPrimaryContainer,
                      ),
                    )
                    : IconButton(
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: "Refresh Library",
                      onPressed: () => provider.loadAudiobooks(),
                    ),
          ),
        ],
      ),
      body: Container(
        decoration: AppTheme.gradientBackground(context),
        child: Stack(
          // Use Stack to overlay messages/indicators
          children: [
            // Main Content (List or Empty Message)
            _buildBody(context, provider, isLandscape),

            // Loading Indicator (Only show during initial load or add folder)
            if (provider.isLoading)
              Container(
                color: Colors.black.withOpacity(0.5),
                child: Center(
                  child: Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: colorScheme.primary),
                          const SizedBox(height: 16),
                          Text(
                            "Loading Library...",
                            style: TextStyle(
                              fontSize: 16,
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Error/Info Message
            if (provider.errorMessage != null && !provider.isLoading)
              _buildErrorMessage(context, provider),
          ],
        ),
      ),
      // Fancy floating action button
      floatingActionButton: AnimatedScale(
        scale: provider.isLoading ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: FloatingActionButton.extended(
          onPressed:
              provider.isLoading ? null : () => provider.addAudiobookFolder(),
          elevation: 4,
          label: const Text('Add Book'),
          icon: const Icon(Icons.add_rounded),
          tooltip: 'Add Audiobook Folder',
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AudiobookProvider provider,
    bool isLandscape,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    if (provider.audiobooks.isEmpty && !provider.isLoading) {
      // Show add folder message if empty and not loading/no error
      if (provider.errorMessage == null &&
          !provider.permissionPermanentlyDenied) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Empty library illustration
                Icon(
                  Icons.menu_book_outlined,
                  size: 80,
                  color: colorScheme.onSurface.withOpacity(0.3),
                ),
                const SizedBox(height: 24),
                Text(
                  'Your library is empty',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap the + button to add an audiobook folder.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 40),
                // Help arrow pointing to FAB
                Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 30),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Tap here',
                          style: TextStyle(
                            fontSize: 14,
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Icon(
                          Icons.arrow_downward_rounded,
                          color: colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        // If there's an error or permission issue, the error message overlay will show
        return const SizedBox.shrink(); // Return empty space, error handled elsewhere
      }
    } else if (provider.audiobooks.isNotEmpty) {
      // For landscape mode, we'll use a grid view instead of a list
      if (isLandscape) {
        return _buildGridView(context, provider);
      } else {
        // Portrait mode - use list view
        return _buildListView(context, provider);
      }
    } else {
      // Return empty container while loading or if there's an error handled by overlay
      return const SizedBox.shrink();
    }
  }

  // Grid view for landscape orientation
  Widget _buildGridView(BuildContext context, AudiobookProvider provider) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Calculate how many items to show per row based on screen width
    final crossAxisCount = screenWidth > 1000 ? 3 : 2;

    return GridView.builder(
      padding: const EdgeInsets.only(
        bottom: 100,
        top: 100, // Padding for app bar
        left: 8,
        right: 8,
      ),
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 2.2, // Width to height ratio of each item
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: provider.audiobooks.length,
      itemBuilder: (context, index) {
        final audiobook = provider.audiobooks[index];
        return GestureDetector(
          onTap: () => _loadLastPositionAndNavigate(context, audiobook),
          onLongPress: () => _showLongPressMenu(context, audiobook, provider),
          child: AudiobookTile(
            key: ValueKey(
              '${audiobook.id}-${DateTime.now().millisecondsSinceEpoch}',
            ),
            audiobook: audiobook,
            customTitle: provider.getTitleForAudiobook(audiobook),
          ),
        );
      },
    );
  }

  // List view for portrait orientation
  Widget _buildListView(BuildContext context, AudiobookProvider provider) {
    return ListView.builder(
      padding: const EdgeInsets.only(
        bottom: 100,
        top: 100, // Padding for app bar
      ),
      physics: const BouncingScrollPhysics(),
      itemCount: provider.audiobooks.length,
      itemBuilder: (context, index) {
        final audiobook = provider.audiobooks[index];
        return GestureDetector(
          onTap: () => _loadLastPositionAndNavigate(context, audiobook),
          onLongPress: () => _showLongPressMenu(context, audiobook, provider),
          child: AudiobookTile(
            key: ValueKey(
              '${audiobook.id}-${DateTime.now().millisecondsSinceEpoch}',
            ),
            audiobook: audiobook,
            customTitle: provider.getTitleForAudiobook(audiobook),
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
        elevation: 6,
        borderRadius: BorderRadius.circular(16),
        color:
            provider.permissionPermanentlyDenied
                ? Colors.orange[800]
                : colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  provider.errorMessage!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // Show settings button only if permission is permanently denied
              if (provider.permissionPermanentlyDenied)
                TextButton.icon(
                  icon: const Icon(Icons.settings, color: Colors.white),
                  label: const Text(
                    "Settings",
                    style: TextStyle(color: Colors.white),
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
