import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;
import '../models/reading_statistics.dart';
import '../providers/audiobook_provider.dart';
import '../providers/audiobook_provider.dart';

class DailyJournalWidget extends ConsumerStatefulWidget {
  final Map<String, DailyStats> dailyStats;
  final DateTime initialDate;
  final Color seedColor;
  final ValueChanged<DateTime>? onDateChanged;

  const DailyJournalWidget({
    super.key,
    required this.dailyStats,
    required this.initialDate,
    required this.seedColor,
    this.onDateChanged,
  });

  @override
  ConsumerState<DailyJournalWidget> createState() => _DailyJournalWidgetState();
}

class _DailyJournalWidgetState extends ConsumerState<DailyJournalWidget> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
  }

  // Update selected date if initialDate changes (e.g. from parent state update)
  @override
  void didUpdateWidget(DailyJournalWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialDate != widget.initialDate) {
      _selectedDate = widget.initialDate;
    }
  }

  void _changeDay(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
    widget.onDateChanged?.call(_selectedDate);
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return '${hours}h ${remainingMinutes}m';
  }
  
  String _getDateString(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  DailyStats get _currentStats {
    final dateString = _getDateString(_selectedDate);
    return widget.dailyStats[dateString] ?? DailyStats.empty(dateString);
  }

  @override
  Widget build(BuildContext context) {
    final stats = _currentStats;
    final dateFormat = DateFormat('EEEE, MMM d, y');
    
    // Check if selected date is today
    final now = DateTime.now();
    final isToday = _selectedDate.year == now.year && 
                   _selectedDate.month == now.month && 
                   _selectedDate.day == now.day;
                   
    final isFuture = _selectedDate.isAfter(now);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withAlpha(200), // Helper for opacity
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: widget.seedColor.withAlpha(30),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => _changeDay(-1),
                  icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
                  color: widget.seedColor,
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        isToday ? 'Today' : dateFormat.format(_selectedDate),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isToday)
                        Text(
                          dateFormat.format(_selectedDate),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: isToday && !isFuture ? null : () {
                    if (!isToday) _changeDay(1);
                  },
                  icon: const Icon(Icons.arrow_forward_ios_rounded, size: 20),
                  color: isToday ? Colors.grey.withAlpha(100) : widget.seedColor,
                ),
              ],
            ),
          ),
          
          const Divider(height: 1),
          
          // Summary
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: Column(
              children: [
                Text(
                  _formatDuration(stats.totalSeconds),
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: widget.seedColor,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'TOTAL READING TIME',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
          ),
          
          // Books Section Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Text(
                  'BOOKS READ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: widget.seedColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Divider(
                    color: widget.seedColor.withAlpha(50),
                    thickness: 1,
                  ),
                ),
              ],
            ),
          ),
          
          // Book List
          if (stats.bookDurations.isEmpty)
             Padding(
              padding: const EdgeInsets.only(bottom: 32.0),
              child: Text(
                'No reading activity recorded',
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: stats.bookDurations.length,
              itemBuilder: (context, index) {
                final bookId = stats.bookDurations.keys.elementAt(index);
                final duration = stats.bookDurations[bookId]!;
                
                // Fetch book details
                final audiobookPrv = provider.Provider.of<AudiobookProvider>(context);
                // Find book safely
                final book = audiobookPrv.audiobooks.where((b) => b.id == bookId).firstOrNull;
                
                final title = book?.title ?? 'Unknown Audiobook';
                final author = book?.author ?? 'Unknown Author';
                
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  leading: Container(
                    width: 40,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: Colors.grey.withAlpha(50),
                      image: (book?.coverArt != null) 
                        ? DecorationImage(
                            image: MemoryImage(book!.coverArt!),
                            fit: BoxFit.cover,
                          ) 
                        : null,
                    ),
                    child: (book?.coverArt == null)
                        ? Icon(Icons.book, size: 20, color: widget.seedColor)
                        : null,
                  ),
                  title: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: Text(
                    author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: widget.seedColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _formatDuration(duration),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: widget.seedColor,
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
