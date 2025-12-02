import 'package:flutter/material.dart';
import '../models/reading_statistics.dart';

/// GitHub-style contribution heatmap for monthly reading activity
class MonthlyHeatmap extends StatefulWidget {
  final Map<String, DailyStats> dailyStats;
  final DateTime currentMonth;
  final Function(DateTime) onMonthChanged;
  final Function(String, DailyStats) onDayTapped;
  final Color seedColor;

  const MonthlyHeatmap({
    super.key,
    required this.dailyStats,
    required this.currentMonth,
    required this.onMonthChanged,
    required this.onDayTapped,
    required this.seedColor,
  });

  @override
  State<MonthlyHeatmap> createState() => _MonthlyHeatmapState();
}

class _MonthlyHeatmapState extends State<MonthlyHeatmap> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Get days in current month
    final year = widget.currentMonth.year;
    final month = widget.currentMonth.month;
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);
    final daysInMonth = lastDay.day;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month navigation
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: () {
                    final prevMonth = DateTime(year, month - 1);
                    widget.onMonthChanged(prevMonth);
                  },
                ),
                Text(
                  _getMonthName(month, year),
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: () {
                    final nextMonth = DateTime(year, month + 1);
                    // Don't allow future months
                    if (nextMonth.isBefore(DateTime.now()) ||
                        nextMonth.month == DateTime.now().month) {
                      widget.onMonthChanged(nextMonth);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Day labels
            _buildDayLabels(textTheme, colorScheme),
            const SizedBox(height: 8),

            // Calendar grid
            _buildCalendarGrid(
              year,
              month,
              daysInMonth,
              firstDay.weekday,
              colorScheme,
            ),
            const SizedBox(height: 16),

            // Legend
            _buildLegend(textTheme, colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildDayLabels(TextTheme textTheme, ColorScheme colorScheme) {
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: days.map((day) {
        return Expanded(
          child: Center(
            child: Text(
              day,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCalendarGrid(
    int year,
    int month,
    int daysInMonth,
    int firstWeekday,
    ColorScheme colorScheme,
  ) {
    final weeks = <Widget>[];
    var currentDay = 1;

    // Adjust firstWeekday: DateTime uses Monday=1, we want Monday=0
    final offset = firstWeekday - 1;

    // Build weeks
    while (currentDay <= daysInMonth) {
      final days = <Widget>[];

      for (var i = 0; i < 7; i++) {
        if (weeks.isEmpty && i < offset) {
          // Empty cell before first day
          days.add(Expanded(child: Container()));
        } else if (currentDay <= daysInMonth) {
          // Day cell
          final day = currentDay;
          final dateString =
              '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
          final stats = widget.dailyStats[dateString] ?? DailyStats.empty(dateString);

          days.add(
            Expanded(
              child: _buildDayCell(day, stats, dateString, colorScheme),
            ),
          );
          currentDay++;
        } else {
          // Empty cell after last day
          days.add(Expanded(child: Container()));
        }
      }

      weeks.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: days),
        ),
      );
    }

    return Column(children: weeks);
  }

  Widget _buildDayCell(
    int day,
    DailyStats stats,
    String dateString,
    ColorScheme colorScheme,
  ) {
    final intensity = stats.intensityLevel;
    final color = _getColorForIntensity(intensity, colorScheme);

    return GestureDetector(
      onTap: () {
        if (stats.totalMinutes > 0) {
          widget.onDayTapped(dateString, stats);
        }
      },
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: stats.totalMinutes > 0
                ? widget.seedColor.withOpacity(0.3)
                : colorScheme.outlineVariant,
            width: stats.totalMinutes > 0 ? 1.5 : 0.5,
          ),
        ),
        child: Center(
          child: Text(
            day.toString(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: stats.totalMinutes > 0 ? FontWeight.w600 : FontWeight.normal,
              color: intensity >= 3
                  ? Colors.white
                  : stats.totalMinutes > 0
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Color _getColorForIntensity(int intensity, ColorScheme colorScheme) {
    switch (intensity) {
      case 0:
        return colorScheme.surfaceContainerLow;
      case 1:
        return widget.seedColor.withOpacity(0.2);
      case 2:
        return widget.seedColor.withOpacity(0.4);
      case 3:
        return widget.seedColor.withOpacity(0.7);
      case 4:
        return widget.seedColor;
      default:
        return colorScheme.surfaceContainerLow;
    }
  }

  Widget _buildLegend(TextTheme textTheme, ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Less',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        for (var i = 0; i <= 4; i++) ...[
          Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: _getColorForIntensity(i, colorScheme),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: colorScheme.outlineVariant,
                width: 0.5,
              ),
            ),
          ),
        ],
        const SizedBox(width: 8),
        Text(
          'More',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String _getMonthName(int month, int year) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[month - 1]} $year';
  }
}
