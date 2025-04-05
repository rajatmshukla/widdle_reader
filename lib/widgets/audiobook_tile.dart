import 'package:flutter/material.dart';
import '../models/audiobook.dart';
import '../utils/helpers.dart'; // Import helpers for formatDuration and buildCoverWidget

class AudiobookTile extends StatelessWidget {
  final Audiobook audiobook;
  final VoidCallback onTap;

  const AudiobookTile({
    super.key, // Use super parameters
    required this.audiobook,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // context is available here
    return Card(
      // Use theme card color implicitly or define explicitly if needed
      // color: Theme.of(context).cardTheme.color,
      elevation: Theme.of(context).cardTheme.elevation ?? 0,
      margin:
          Theme.of(context).cardTheme.margin ??
          const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      shape: Theme.of(context).cardTheme.shape,
      child: InkWell(
        // Use InkWell for ripple effect on tap
        borderRadius: BorderRadius.circular(8.0), // Match card shape for ripple
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              ClipRRect(
                // Clip the cover image corners
                borderRadius: BorderRadius.circular(4.0),
                // *** FIXED: Pass context as the first argument ***
                child: buildCoverWidget(context, audiobook, size: 60.0),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      audiobook.title,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Total Duration: ${formatDuration(audiobook.totalDuration)}',
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${audiobook.chapters.length} Chapters',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ), // Indicator for tap action
            ],
          ),
        ),
      ),
    );
  }
}
