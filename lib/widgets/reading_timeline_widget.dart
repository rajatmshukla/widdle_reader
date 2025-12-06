import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/reading_session.dart';
import '../services/storage_service.dart';
import 'dart:io';

/// Interactive horizontal timeline showing reading sessions
class ReadingTimelineWidget extends StatelessWidget {
  final List<ReadingSession> sessions;
  final DateTime selectedDate;
  final Function(DateTime)? onDateChanged;

  const ReadingTimelineWidget({
    super.key,
    required this.sessions,
    required this.selectedDate,
    this.onDateChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Group sessions by date
    final sessionsByDate = <String, List<ReadingSession>>{};
    for (final session in sessions) {
      sessionsByDate.putIfAbsent(session.dateString, () => []).add(session);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.timeline_rounded,
                color: colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Reading Timeline',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        if (sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.auto_stories_outlined,
                    size: 64,
                    color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No reading sessions yet',
                    style: textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start reading to see your journey!',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: 160,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                return _SessionBubble(
                  session: session,
                  isFirst: index == 0,
                  isLast: index == sessions.length - 1,
                );
              },
            ),
          ),
      ],
    );
  }
}

class _SessionBubble extends StatefulWidget {
  final ReadingSession session;
  final bool isFirst;
  final bool isLast;

  const _SessionBubble({
    required this.session,
    required this.isFirst,
    required this.isLast,
  });

  @override
  State<_SessionBubble> createState() => _SessionBubbleState();
}

class _SessionBubbleState extends State<_SessionBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;
  final StorageService _storageService = StorageService();
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IconData _getTimeOfDayIcon() {
    final hour = widget.session.startTime.hour;
    if (hour >= 5 && hour < 12) return Icons.wb_sunny; // Morning
    if (hour >= 12 && hour < 17) return Icons.wb_sunny_outlined; // Afternoon
    if (hour >= 17 && hour < 21) return Icons.wb_twilight; // Evening
    return Icons.nightlight_round; // Night
  }

  Color _getTimeOfDayColor() {
    final hour = widget.session.startTime.hour;
    if (hour >= 5 && hour < 12) return const Color(0xFFFFB84D); // Morning
    if (hour >= 12 && hour < 17) return const Color(0xFFFF9500); // Afternoon
    if (hour >= 17 && hour < 21) return const Color(0xFFFF6B6B); // Evening
    return const Color(0xFF6B66FF); // Night
  }

  String _formatTime(DateTime time) {
    return DateFormat('h:mm a').format(time);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final timeColor = _getTimeOfDayColor();

    return SlideTransition(
      position: _slideAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: GestureDetector(
          onTap: () {
            setState(() => _isExpanded = !_isExpanded);
            _showSessionDetails(context);
          },
          child: Container(
            width: 120,
            margin: const EdgeInsets.only(right: 16),
            child: Column(
              children: [
                // Time indicator
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: timeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getTimeOfDayIcon(),
                        size: 14,
                        color: timeColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatTime(widget.session.startTime),
                        style: textTheme.labelSmall?.copyWith(
                          color: timeColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Main bubble
                FutureBuilder<String?>(
                  future: _storageService.getCachedCoverArtPath(
                    widget.session.audiobookId,
                  ),
                  builder: (context, snapshot) {
                    return Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            colorScheme.primaryContainer,
                            colorScheme.secondaryContainer,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        image: snapshot.hasData && snapshot.data != null
                            ? DecorationImage(
                                image: FileImage(File(snapshot.data!)),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: snapshot.hasData && snapshot.data != null
                          ? null
                          : Icon(
                              Icons.book,
                              size: 32,
                              color: colorScheme.onPrimaryContainer,
                            ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                // Duration badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.session.durationSeconds < 60
                        ? '${widget.session.durationSeconds}s'
                        : '${widget.session.durationMinutes} min',
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onTertiaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSessionDetails(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.auto_stories,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Reading Session',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Details
            _DetailRow(
              icon: Icons.schedule,
              label: 'Duration',
              value: widget.session.durationSeconds < 60
                  ? '${widget.session.durationSeconds} seconds'
                  : '${widget.session.durationMinutes} minutes',
              color: colorScheme.primary,
            ),
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.access_time,
              label: 'Time',
              value:
                  '${_formatTime(widget.session.startTime)} - ${_formatTime(widget.session.endTime)}',
              color: _getTimeOfDayColor(),
            ),
            if (widget.session.chapterName != null) ...[
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.bookmark,
                label: 'Chapter',
                value: widget.session.chapterName!,
                color: colorScheme.tertiary,
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
