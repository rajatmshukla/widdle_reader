import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class WeeklyBarChart extends StatelessWidget {
  final List<int> dailyMinutes;
  final Color barColor;

  const WeeklyBarChart({
    super.key,
    required this.dailyMinutes,
    required this.barColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Find max value for Y axis scaling (add some buffer)
    int maxMinutes = 0;
    for (var m in dailyMinutes) {
      if (m > maxMinutes) maxMinutes = m;
    }
    final maxY = (maxMinutes > 0 ? maxMinutes : 60) * 1.2;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Weekly Activity',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Minutes read per day',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: barColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Last 7 Days',
                    style: textTheme.labelSmall?.copyWith(
                      color: barColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      tooltipBgColor: colorScheme.inverseSurface,
                      tooltipPadding: const EdgeInsets.all(8),
                      tooltipMargin: 8,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          '${rod.toY.round()} min',
                          TextStyle(
                            color: colorScheme.onInverseSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                          final index = value.toInt();
                          if (index >= 0 && index < days.length) {
                            // Highlight today
                            final todayIndex = DateTime.now().weekday - 1;
                            final isToday = index == todayIndex;
                            
                            return SideTitleWidget(
                              axisSide: meta.axisSide,
                              child: Text(
                                days[index],
                                style: textTheme.labelMedium?.copyWith(
                                  color: isToday 
                                      ? barColor 
                                      : colorScheme.onSurfaceVariant,
                                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(7, (index) {
                    final minutes = index < dailyMinutes.length ? dailyMinutes[index] : 0;
                    final todayIndex = DateTime.now().weekday - 1;
                    final isToday = index == todayIndex;
                    
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: minutes.toDouble(),
                          color: isToday ? barColor : barColor.withOpacity(0.5),
                          width: 16,
                          borderRadius: BorderRadius.circular(6),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: maxY,
                            color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
