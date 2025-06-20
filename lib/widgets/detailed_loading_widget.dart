import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audiobook_provider.dart';

class DetailedLoadingWidget extends StatelessWidget {
  const DetailedLoadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Consumer<AudiobookProvider>(
      builder: (context, provider, child) {
        // Show overlay when loading
        if (!provider.isLoading && !provider.isDetailedLoading) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
          height: double.infinity,
          color: colorScheme.surface.withOpacity(0.9),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                ),
                const SizedBox(height: 16),
                Text(
                  'Loading Audiobooks',
                  style: TextStyle(
                    fontSize: 16,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
} 