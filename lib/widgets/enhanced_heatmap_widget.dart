import 'package:flutter/material.dart';
import '../models/reading_statistics.dart';

/// Enhanced monthly heatmap with gradients and smooth animations
class EnhancedHeatmapWidget extends StatefulWidget {
  final Map<String, DailyStats> dailyStats;
  final DateTime currentMonth;
  final Function(DateTime)? onMonthChanged;
  final Function(String, DailyStats)? onDayTapped;
  final Color seedColor;

  const EnhancedHeatmapWidget({
    super.key,
    required this.dailyStats,
    required this.currentMonth,
    this.onMonthChanged,
    this.onDayTapped,
    required this.seedColor,
  });

  @override
  State<EnhancedHeatmapWidget> createState() => _EnhancedHeatmapWidgetState();
}

class _EnhancedHeatmapWidgetState extends State<EnhancedHeatmapWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();
  }

  @override
  void didUpdateWidget(EnhancedHeatmapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentMonth != widget.currentMonth) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<List<DateTime?>> _generateMonthGrid() {
    final firstDay = DateTime(widget.currentMonth.year, widget.currentMonth.month, 1);
    final lastDay = DateTime(widget.currentMonth.year, widget.currentMonth.month + 1, 0);
    
    final weeks = <List<DateTime?>>[];
    var currentWeek = List<DateTime?>.filled(7, null);
    
    // Fill in days before first of month
    final firstWeekday = firstDay.weekday % 7; // 0 = Sunday
    for (int i = 0; i < firstWeekday; i++) {
      currentWeek[i] = null;
    }
    
    // Fill in all days of the month
    for (int day = 1; day <= lastDay.day; day++) {
      final date = DateTime(widget.currentMonth.year, widget.currentMonth.month, day);
      final weekday = date.weekday % 7;
      
      currentWeek[weekday] = date;
      
      if (weekday == 6 || day == lastDay.day) {
        weeks.add(List.from(currentWeek));
        currentWeek = List<DateTime?>.filled(7, null);
      }
    }
    
    return weeks;
  }

  int _getMaxMinutes() {
    if (widget.dailyStats.isEmpty) return 60;
    return widget.dailyStats.values
        .map((stat) => stat.totalMinutes)
        .reduce((a, b) => a > b ? a : b)
        .clamp(1, 300);
  }

  Color _getGradientColor(int minutes, int maxMinutes) {
    if (minutes == 0) return Colors.transparent;
    
    final intensity = (minutes / maxMinutes).clamp(0.0, 1.0);
    
    // Create gradient from light to vibrant
    return Color.lerp(
      widget.seedColor.withOpacity(0.2),
      widget.seedColor,
      intensity,
    )!;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final weeks = _generateMonthGrid();
    final maxMinutes = _getMaxMinutes();

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month header with navigation
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    final newMonth = DateTime(
                      widget.currentMonth.year,
                      widget.currentMonth.month - 1,
                    );
                    widget.onMonthChanged?.call(newMonth);
                  },
                ),
                Expanded(
                  child: Text(
                    _formatMonth(widget.currentMonth),
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    final newMonth = DateTime(
                      widget.currentMonth.year,
                      widget.currentMonth.month + 1,
                    );
                    widget.onMonthChanged?.call(newMonth);
                  },
                ),
              ],
            ),
          ),
          
          // Weekday labels
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: ['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((day) {
                return SizedBox(
                  width: 40,
                  child: Text(
                    day,
                    textAlign: TextAlign.center,
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Calendar grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: weeks.map((week) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: week.map((date) {
                      if (date == null) {
                        return const SizedBox(width: 40, height: 40);
                      }
                      
                      final dateString = _formatDateString(date);
                      final stats = widget.dailyStats[dateString] ?? DailyStats.empty(dateString);
                      final minutes = stats.totalMinutes;
                      final color = _getGradientColor(minutes, maxMinutes);
                      final isToday = _isToday(date);
                      
                      return _DayCell(
                        date: date,
                        color: color,
                        isToday: isToday,
                        stats: stats,
                        onTap: () {
                          widget.onDayTapped?.call(dateString, stats);
                        },
                      );
                    }).toList(),
                  ),
                );
              }).toList(),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Legend
          _buildLegend(context, maxMinutes),
        ],
      ),
    );
  }

  Widget _buildLegend(BuildContext context, int maxMinutes) {
    final textTheme = Theme.of(context).textTheme;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Less',
            style: textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          ...List.generate(5, (index) {
            final intensity = index / 4;
            final color = Color.lerp(
              widget.seedColor.withOpacity(0.2),
              widget.seedColor,
              intensity,
            )!;
            
            return Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                boxShadow: intensity > 0.5
                    ? [
                        BoxShadow(
                          color: color.withOpacity(0.3),
                          blurRadius: 4,
                        ),
                      ]
                    : null,
              ),
            );
          }),
          const SizedBox(width: 8),
          Text(
            'More',
            style: textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _formatMonth(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  String _formatDateString(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}

class _DayCell extends StatefulWidget {
  final DateTime date;
  final Color color;
  final bool isToday;
  final DailyStats stats;
  final VoidCallback onTap;

  const _DayCell({
    required this.date,
    required this.color,
    required this.isToday,
    required this.stats,
    required this.onTap,
  });

  @override
  State<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<_DayCell>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
        _controller.forward();
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
        _controller.reverse();
      },
      child: AnimatedScale(
        scale: _isPressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(8),
            border: widget.isToday
                ? Border.all(
                    color: colorScheme.primary,
                    width: 2,
                  )
                : null,
            boxShadow: widget.stats.totalMinutes > 0
                ? [
                    BoxShadow(
                      color: widget.color.withOpacity(0.4),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              '${widget.date.day}',
              style: textTheme.labelMedium?.copyWith(
                color: widget.stats.totalMinutes > 0
                    ? Colors.white
                    : colorScheme.onSurface,
                fontWeight: widget.isToday
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
