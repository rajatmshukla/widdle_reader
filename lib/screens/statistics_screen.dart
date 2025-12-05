import 'package:flutter/material.dart';
import 'package:provider/provider.dart' as provider;
import '../services/statistics_service.dart';
import '../providers/theme_provider.dart';
import '../widgets/app_logo.dart';
import '../widgets/monthly_heatmap.dart';
import '../widgets/weekly_bar_chart.dart';
import '../widgets/stat_card.dart';
import '../widgets/reading_history_list.dart';
import '../models/reading_statistics.dart';
import '../models/reading_session.dart';
import '../theme.dart';

/// Main statistics screen showing reading activity and insights
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final StatisticsService _statsService = StatisticsService();
  DateTime _currentMonth = DateTime.now();
  Map<String, DailyStats> _dailyStats = {};
  int _currentStreak = 0;
  int _longestStreak = 0;
  double _avgSessionTime = 0.0;
  double _avgSessionsPerDay = 0.0;
  int _minutesThisWeek = 0;
  int _sessionsThisWeek = 0;
  int _minutesThisMonth = 0;
  int _sessionsThisMonth = 0;
  List<int> _weeklyDailyMinutes = [];
  List<ReadingSession> _recentSessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    setState(() => _loading = true);

    try {
      // Load streak data
      final streak = await _statsService.getStreak();
      _currentStreak = streak.currentStreak;
      _longestStreak = streak.longestStreak;

      // Load monthly heatmap data
      final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
      final lastDay = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
      _dailyStats = await _statsService.getDailyStatsRange(firstDay, lastDay);

      // Load insights
      _avgSessionTime = await _statsService.getAverageSessionDuration();
      _avgSessionsPerDay = await _statsService.getAverageSessionsPerDay();
      _minutesThisWeek = await _statsService.getTotalMinutesThisWeek();
      _sessionsThisWeek = await _statsService.getTotalSessionsThisWeek();
      _minutesThisMonth = await _statsService.getTotalMinutesThisMonth();
      _sessionsThisMonth = await _statsService.getTotalSessionsThisMonth();
      
      // Load new data for charts and history
      _weeklyDailyMinutes = await _statsService.getWeeklyDailyMinutes();
      _recentSessions = await _statsService.getRecentSessions(10);
      
      debugPrint('📊 Loaded ${_recentSessions.length} recent sessions');
      
    } catch (e) {
      debugPrint('Error loading statistics: $e');
    }

    setState(() => _loading = false);
  }

  void _onMonthChanged(DateTime newMonth) {
    setState(() {
      _currentMonth = newMonth;
    });
    _loadStatistics();
  }

  void _onDayTapped(String dateString, DailyStats stats) {
    showModalBottomSheet(
      context: context,
      builder: (context) => _buildDayDetailsSheet(dateString, stats),
    );
  }

  Widget _buildDayDetailsSheet(String dateString, DailyStats stats) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date header
          Row(
            children: [
              Icon(Icons.calendar_today_rounded, color: colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                _formatDate(dateString),
                style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Stats
          _buildStatRow(Icons.timer_outlined, 'Total Reading Time',
              '${stats.totalMinutes} minutes', colorScheme, textTheme),
          const SizedBox(height: 12),
          _buildStatRow(Icons.auto_stories_rounded, 'Sessions',
              '${stats.sessionCount}', colorScheme, textTheme),
          const SizedBox(height: 12),
          _buildStatRow(Icons.menu_book_rounded, 'Chapters Read',
              '${stats.pagesRead}', colorScheme, textTheme),
          const SizedBox(height: 12),
          _buildStatRow(Icons.library_books_rounded, 'Books Touched',
              '${stats.audiobooksRead.length}', colorScheme, textTheme),

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(
    IconData icon,
    String label,
    String value,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Row(
      children: [
        Icon(icon, color: colorScheme.primary, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  String _formatDate(String dateString) {
    final parts = dateString.split('-');
    if (parts.length != 3) return dateString;

    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final day = int.parse(parts[2]);

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    return '${months[month - 1]} $day, $year';
  }

  Future<void> _showResetDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_rounded,
                color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 12),
            const Text('Reset All Statistics?'),
          ],
        ),
        content: const Text(
          'Are you sure you want to remove all your hard-earned stats?\n\n'
          'This action cannot be undone. All your reading history, streaks, '
          'and achievements will be permanently deleted.\n\n'
          'A backup will be created before resetting.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Reset Stats'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await _statsService.resetAllStatistics();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Statistics reset successfully'),
              behavior: SnackBarBehavior.floating,
            ),
          );

          // Reload statistics
          _loadStatistics();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error resetting statistics: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = provider.Provider.of<ThemeProvider>(context);
    final seedColor = themeProvider.seedColor;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: AppLogo(size: 32, showTitle: false),
            ),
            const SizedBox(width: 12),
            const Text('Reading Statistics'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadStatistics,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              if (value == 'reset') {
                _showResetDialog();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'reset',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever_rounded, color: Colors.red),
                    SizedBox(width: 12),
                    Text('Reset Statistics'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: AppTheme.gradientBackground(context),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadStatistics,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Summary Header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '${(_minutesThisWeek / 60).toStringAsFixed(1)}',
                              style: textTheme.displayMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'hours this week',
                              style: textTheme.titleMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 2. Weekly Chart
                      WeeklyBarChart(
                        dailyMinutes: _weeklyDailyMinutes,
                        barColor: seedColor,
                      ),
                      const SizedBox(height: 24),

                      // 3. Bento Grid (Insights)
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 1.5,
                        children: [
                          StatCard(
                            label: 'Current Streak',
                            value: '$_currentStreak',
                            unit: 'days',
                            icon: Icons.local_fire_department_rounded,
                            iconColor: Colors.orange,
                          ),
                          StatCard(
                            label: 'Longest Streak',
                            value: '$_longestStreak',
                            unit: 'days',
                            icon: Icons.emoji_events_rounded,
                            iconColor: Colors.amber,
                          ),
                          StatCard(
                            label: 'Avg Session',
                            value: '${_avgSessionTime.round()}',
                            unit: 'minutes',
                            icon: Icons.timer_outlined,
                            iconColor: Colors.blue,
                          ),
                          StatCard(
                            label: 'Books Read',
                            value: '${_sessionsThisMonth > 0 ? 1 : 0}', // Simplified for now, ideally unique books
                            unit: 'this month',
                            icon: Icons.menu_book_rounded,
                            iconColor: Colors.green,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // 4. Monthly Heatmap
                      Text(
                        'Monthly Activity',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      MonthlyHeatmap(
                        dailyStats: _dailyStats,
                        currentMonth: _currentMonth,
                        onMonthChanged: _onMonthChanged,
                        onDayTapped: _onDayTapped,
                        seedColor: seedColor,
                      ),
                      const SizedBox(height: 24),

                      // 5. History Log
                      ReadingHistoryList(sessions: _recentSessions),
                      
                      const SizedBox(height: 40), // Bottom padding
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
