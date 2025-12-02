import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/reading_session.dart';
import '../services/storage_service.dart';
import 'dart:io';

class ReadingHistoryList extends StatelessWidget {
  final List<ReadingSession> sessions;
  final StorageService _storageService = StorageService();

  ReadingHistoryList({
    super.key,
    required this.sessions,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (sessions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No recent history',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            'Recent History',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: sessions.length,
          separatorBuilder: (context, index) => Divider(
            height: 1,
            indent: 72,
            color: colorScheme.outlineVariant.withOpacity(0.5),
          ),
          itemBuilder: (context, index) {
            final session = sessions[index];
            return _buildSessionTile(context, session);
          },
        ),
      ],
    );
  }

  Widget _buildSessionTile(BuildContext context, ReadingSession session) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return FutureBuilder<String?>(
      future: _storageService.getCachedCoverArtPath(session.audiobookId),
      builder: (context, snapshot) {
        final coverPath = snapshot.data;
        
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              image: coverPath != null
                  ? DecorationImage(
                      image: FileImage(File(coverPath)),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: coverPath == null
                ? Icon(Icons.book, size: 24, color: colorScheme.primary)
                : null,
          ),
          title: Text(
            session.chapterName ?? 'Unknown Chapter',
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            _formatDate(session.endTime),
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${session.durationMinutes} min',
              style: textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes} mins ago';
      }
      return '${difference.inHours} hours ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return DateFormat('EEEE').format(date); // e.g. "Monday"
    } else {
      return DateFormat('MMM d').format(date); // e.g. "Oct 12"
    }
  }
}
