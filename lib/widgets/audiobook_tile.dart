import 'package:flutter/material.dart';
import '../models/audiobook.dart';
import '../utils/helpers.dart';

class AudiobookTile extends StatelessWidget {
  final Audiobook audiobook;
  final String? customTitle;
  final VoidCallback? onTap;

  const AudiobookTile({
    super.key,
    required this.audiobook,
    this.customTitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Use custom title if provided, otherwise use the original title
    final displayTitle = customTitle ?? audiobook.title;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Card(
        elevation: 4,
        clipBehavior:
            Clip.antiAlias, // Ensures child doesn't overflow rounded corners
        child: InkWell(
          onTap: onTap,
          splashColor: colorScheme.primary.withOpacity(0.3),
          highlightColor: colorScheme.primaryContainer.withOpacity(0.3),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                // Cover image with rounded corners and shadow
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: buildCoverWidget(
                      context,
                      audiobook,
                      size: 80.0,
                      customTitle: displayTitle,
                    ),
                  ),
                ),

                const SizedBox(width: 16),

                // Book details with improved typography
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title with emphasis
                      Text(
                        displayTitle,
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      const SizedBox(height: 8),

                      // Duration with icon
                      Row(
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 14,
                            color: colorScheme.onSurfaceVariant.withOpacity(
                              0.7,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            formatDuration(audiobook.totalDuration),
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant.withOpacity(
                                0.7,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 4),

                      // Chapter count with icon
                      Row(
                        children: [
                          Icon(
                            Icons.library_books_outlined,
                            size: 14,
                            color: colorScheme.onSurfaceVariant.withOpacity(
                              0.7,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${audiobook.chapters.length} Chapters',
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant.withOpacity(
                                0.7,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Long-press hint
                Column(
                  children: [
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: colorScheme.primary.withOpacity(0.7),
                    ),
                    const SizedBox(height: 4),
                    Icon(
                      Icons.touch_app,
                      size: 12,
                      color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
