import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// Import permission_handler for openAppSettings

import '../providers/audiobook_provider.dart';
import '../widgets/audiobook_tile.dart';
import '../models/audiobook.dart';
import '../services/storage_service.dart'; // Keep for loading position

class LibraryScreen extends StatelessWidget {
  // Use super parameters
  const LibraryScreen({super.key});

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

    // Prepare arguments for the player screen
    Map<String, dynamic> arguments = {'audiobook': audiobook};
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

    Navigator.pushNamed(context, '/player', arguments: arguments);
  }

  @override
  Widget build(BuildContext context) {
    // Use watch for automatic rebuilds when provider notifies listeners
    final provider = context.watch<AudiobookProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Widdle Reader Library'),
        actions: [
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh Widdle Reader",
            onPressed:
                provider.isLoading
                    ? null
                    : () => provider.loadAudiobooks(), // Disable while loading
          ),
        ],
      ),
      body: Stack(
        // Use Stack to overlay messages/indicators
        children: [
          // Main Content (List or Empty Message)
          _buildBody(context, provider),

          // Loading Indicator (Only show during initial load or add folder)
          if (provider.isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 15),
                    Text(
                      "Loading...",
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),

          // Error/Info Message Snackbar-like display
          if (provider.errorMessage != null && !provider.isLoading)
            _buildErrorMessage(context, provider),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed:
            provider.isLoading
                ? null
                : () => provider.addAudiobookFolder(), // Disable while loading
        tooltip: 'Add Audiobook Folder',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AudiobookProvider provider) {
    // Don't show loading here if it's handled by the overlay Stack
    // if (provider.isLoading && provider.audiobooks.isEmpty) {
    //   return const Center(child: CircularProgressIndicator());
    // }

    if (provider.audiobooks.isEmpty && !provider.isLoading) {
      // Show add folder message if empty and not loading/no error
      if (provider.errorMessage == null &&
          !provider.permissionPermanentlyDenied) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(30.0),
            child: Text(
              'No audiobooks found.\nTap the + button to add a folder.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ),
        );
      } else {
        // If there's an error or permission issue, the error message overlay will show
        return const SizedBox.shrink(); // Return empty space, error handled elsewhere
      }
    } else if (provider.audiobooks.isNotEmpty) {
      // Display the list
      return ListView.builder(
        padding: const EdgeInsets.only(
          bottom: 80,
        ), // Padding to avoid FAB overlap
        itemCount: provider.audiobooks.length,
        itemBuilder: (context, index) {
          final audiobook = provider.audiobooks[index];
          return AudiobookTile(
            audiobook: audiobook,
            // Pass the async function directly
            onTap: () => _loadLastPositionAndNavigate(context, audiobook),
          );
        },
      );
    } else {
      // Return empty container while loading or if there's an error handled by overlay
      return const SizedBox.shrink();
    }
  }

  // Extracted error message widget
  Widget _buildErrorMessage(BuildContext context, AudiobookProvider provider) {
    return Positioned(
      bottom: 80, // Position above FAB
      left: 20,
      right: 20,
      child: Material(
        // Wrap with Material for elevation and shape
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        color:
            provider.permissionPermanentlyDenied
                ? Colors.orange[800]
                : Colors.redAccent.withOpacity(0.9),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  provider.errorMessage!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
              // Show settings button only if permission is permanently denied
              if (provider.permissionPermanentlyDenied)
                IconButton(
                  icon: const Icon(Icons.settings, color: Colors.white),
                  tooltip: "Open App Settings",
                  onPressed:
                      () => provider.openSettings(), // Call provider method
                ),
            ],
          ),
        ),
      ),
    );
  }
}
