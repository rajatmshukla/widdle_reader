import 'package:flutter/material.dart';

/// Card-based panel displaying reading insights and statistics
class InsightsPanel extends StatelessWidget {
  final int currentStreak;
  final int longestStreak;
  final double avgSessionTime;
  final double avgSessionsPerDay;
  final int minutesThisWeek;
  final int sessionsThisWeek;
  final int minutesThisMonth;
  final int sessionsThisMonth;
  final Color seedColor;

  const InsightsPanel({
    super.key,
    required this.currentStreak,
    required this.longestStreak,
    required this.avgSessionTime,
    required this.avgSessionsPerDay,
    required this.minutesThisWeek,
    required this.sessionsThisWeek,
    required this.minutesThisMonth,
    required this.sessionsThisMonth,
    required this.seedColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme =Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          child: Row(
            children: [
              Icon(Icons.insights_rounded, color: colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Reading Insights',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
              ),
            ],
          ),
        ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.5,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          padding: EdgeInsets.zero,
          children: [
            _buildInsightCard(
              context,
              icon: Icons.local_fire_department_rounded,
              iconColor: const Color(0xFFFF6B35),
              label: 'Current Streak',
              value: '$currentStreak',
              unit: currentStreak == 1 ? 'day' : 'days',
            ),
            _buildInsightCard(
              context,
              icon: Icons.emoji_events_rounded,
              iconColor: const Color(0xFFFFD700),
              label: 'Longest Streak',
              value: '$longestStreak',
              unit: longestStreak == 1 ? 'day' : 'days',
            ),
            _buildInsightCard(
              context,
              icon: Icons.timer_outlined,
              iconColor: colorScheme.primary,
              label: 'Avg Session',
              value: avgSessionTime.toStringAsFixed(1),
              unit: 'min',
            ),
            _buildInsightCard(
              context,
              icon: Icons.auto_stories_rounded,
              iconColor: colorScheme.secondary,
              label: 'Sessions/Day',
              value: avgSessionsPerDay.toStringAsFixed(1),
              unit: 'avg',
            ),
            _buildInsightCard(
              context,
              icon: Icons.calendar_today_rounded,
              iconColor: colorScheme.tertiary,
              label: 'This Week',
              value: '$minutesThisWeek',
              unit: 'min • $sessionsThisWeek sessions',
              compactUnit: true,
            ),
            _buildInsightCard(
              context,
              icon: Icons.calendar_month_rounded,
              iconColor: seedColor,
              label: 'This Month',
              value: '$minutesThisMonth',
              unit: 'min • $sessionsThisMonth sessions',
              compactUnit: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInsightCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String unit,
    bool compactUnit = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
                if (!compactUnit)
                  Text(
                    unit,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            if (compactUnit) ...[
              const SizedBox(height: 4),
              Text(
                unit,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
