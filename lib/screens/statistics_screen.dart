import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart' as provider;
import '../services/statistics_service.dart';
import '../providers/theme_provider.dart';
import '../widgets/app_logo.dart';
import '../widgets/progress_ring_widget.dart';
import '../widgets/daily_journal_widget.dart';
import '../widgets/stat_card.dart';
import '../models/reading_statistics.dart';
import '../models/reading_session.dart';
import '../theme.dart';
import 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';
import 'achievement_gallery_screen.dart';
import '../widgets/personality_card.dart';
import '../widgets/challenge_list_widget.dart';
import '../widgets/xp_badge.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/audiobook_provider.dart';
import '../providers/tag_provider.dart';

enum StatsView { snapshot, trends }

/// Revamped statistics screen with immersive reading journey visualization
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> with WidgetsBindingObserver {
  final StatisticsService _statsService = StatisticsService();
  StreamSubscription? _statsSubscription;
  
  DateTime _currentMonth = DateTime.now();
  DateTime _focusedDate = DateTime.now();
  Map<String, DailyStats> _dailyStats = {};
  int _currentStreak = 0;
  int _longestStreak = 0;
  double _avgSessionTime = 0.0;
  int _minutesToday = 0;
  int _minutesThisWeek = 0;
  int _minutesThisMonth = 0;
  int _sessionsThisWeek = 0;
  // Changed to track seconds for live updates
  int _secondsToday = 0;

  bool _loading = true;
  
  // Default daily goal (30 minutes)
  int _dailyGoalMinutes = 30;
  bool _showStreak = true;
  bool _showHoursMode = false; // New state for duration format
  StatsView _currentView = StatsView.snapshot;

  // Trend Data
  Map<int, int> _hourlyActivity = {};
  Map<int, int> _weekdayActivity = {};
  Map<String, int> _genreDistribution = {};
  Map<String, int> _monthlyMomentum = {};
  Map<String, dynamic> _completionFunnel = {'total': 0, 'started': 0, 'completed': 0};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStatistics();
    
    // Listen for real-time updates
    _statsSubscription = _statsService.onStatsUpdated.listen((_) {
      if (mounted) {
        debugPrint('📊 UI: Received real-time stats update - Refreshing display');
        _loadStatistics(showLoading: false);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statsSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('📊 App resumed - refreshing statistics');
      _loadStatistics(showLoading: false);
    }
  }

  Future<void> _loadStatistics({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _loading = true);
    }

    try {
      // Load settings
      _dailyGoalMinutes = await _statsService.getDailyGoal();
      _showStreak = await _statsService.getShowStreak();
      _showHoursMode = await _statsService.getShowHoursAndMinutes();

      // Load streak data
      final streak = await _statsService.getStreak();
      _currentStreak = streak.currentStreak;
      _longestStreak = streak.longestStreak;

      // Load monthly heatmap data (Last 365 days for the full view)
      final now = DateTime.now();
      final oneYearAgo = now.subtract(const Duration(days: 365));
      _dailyStats = await _statsService.getDailyStatsRange(oneYearAgo, now);

      // Load insights
      _avgSessionTime = await _statsService.getAverageSessionDuration();
      _minutesThisWeek = await _statsService.getTotalMinutesThisWeek();
      _minutesThisMonth = await _statsService.getTotalMinutesThisMonth();
      _sessionsThisWeek = await _statsService.getTotalSessionsThisWeek();
      
      // Get today's minutes
      final today = DateTime.now();
      final todayString = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final todayStats = await _statsService.getDailyStats(todayString);
      _secondsToday = todayStats.totalSeconds;
      
      // Load Trend Data
      _hourlyActivity = await _statsService.getHourlyActivity();
      _weekdayActivity = await _statsService.getWeekdayActivity();
      _monthlyMomentum = await _statsService.getMonthlyMomentum();
      
      // Get book tags for genre distribution and calculate completion stats
      if (mounted) {
        final audiobookProvider = provider.Provider.of<AudiobookProvider>(context, listen: false);
        final bookTags = <String, Set<String>>{};
        int completedCount = 0;
        int startedCount = 0;
        
        for (var book in audiobookProvider.audiobooks) {
          bookTags[book.id] = book.tags;
          if (audiobookProvider.isCompletedBook(book.id)) {
            completedCount++;
          } else {
            // Check if played (not new)
            if (!audiobookProvider.isNewBook(book.id)) {
              startedCount++;
            }
          }
        }
        
        _genreDistribution = await _statsService.getGenreDistribution(bookTags);
        _completionFunnel = {
          'total': audiobookProvider.audiobooks.length,
          'started': startedCount,
          'completed': completedCount,
        };
      }
      
    } catch (e) {
      debugPrint('Error loading statistics: $e');
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _showSettingsDialog() async {
    int tempGoal = _dailyGoalMinutes;
    bool tempShowStreak = _showStreak;
    bool tempShowHours = _showHoursMode;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Statistics Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Daily Reading Goal'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: tempGoal.toDouble(),
                      min: 5,
                      max: 120,
                      divisions: 23,
                      label: '$tempGoal min',
                      onChanged: (value) {
                        setState(() => tempGoal = value.round());
                      },
                    ),
                  ),
                  Text('$tempGoal min', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Show Streak'),
                subtitle: const Text('Display your reading streak badge'),
                value: tempShowStreak,
                onChanged: (value) {
                  setState(() => tempShowStreak = value);
                },
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text('Show Hours and Minutes'),
                subtitle: const Text('Format durations as hrs and mins'),
                value: tempShowHours,
                onChanged: (value) {
                  setState(() => tempShowHours = value);
                },
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await _statsService.setDailyGoal(tempGoal);
                await _statsService.setShowStreak(tempShowStreak);
                await _statsService.setShowHoursAndMinutes(tempShowHours);
                Navigator.pop(context);
                _loadStatistics(); // Reload to apply changes
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showResetDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, color: Colors.red),
            SizedBox(width: 12),
            Text('Reset Statistics?'),
          ],
        ),
        content: const Text(
          'This will permanently delete all your reading statistics, '
          'sessions, streaks, and achievements. This action cannot be undone.\n\n'
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
    final colorScheme = Theme.of(context).colorScheme;

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
            Text(
              'Reading Journey',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
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
              } else if (value == 'settings') {
                _showSettingsDialog();
              } else if (value == 'achievements') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AchievementGalleryScreen(),
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'achievements',
                child: Row(
                  children: [
                    Icon(Icons.emoji_events_rounded),
                    SizedBox(width: 12),
                    Text('Achievements'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings_rounded),
                    SizedBox(width: 12),
                    Text('Settings'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'reset',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever_rounded, color: Colors.red),
                    SizedBox(width: 12),
                    Text('Reset Stats', style: TextStyle(color: Colors.red)),
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
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    // View Toggle
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SegmentedButton<StatsView>(
                        segments: const [
                          ButtonSegment<StatsView>(
                            value: StatsView.snapshot,
                            label: Text('Snapshot'),
                            icon: Icon(Icons.dashboard_rounded),
                          ),
                          ButtonSegment<StatsView>(
                            value: StatsView.trends,
                            label: Text('Trends'),
                            icon: Icon(Icons.insights_rounded),
                          ),
                        ],
                        selected: {_currentView},
                        onSelectionChanged: (Set<StatsView> newSelection) {
                          setState(() {
                            _currentView = newSelection.first;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _currentView == StatsView.snapshot 
                            ? _buildSnapshotView() 
                            : _buildTrendsView(),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSnapshotView() {
    final colorScheme = Theme.of(context).colorScheme;
    
    return SingleChildScrollView(
      key: const ValueKey('snapshot'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. XP Badge
          const Padding(
            padding: EdgeInsets.only(top: 8.0, bottom: 4.0),
            child: Center(
              child: XPBadge(),
            ),
          ),
          
          const SizedBox(height: 4),

          // 2. Goal Progress (Embedded in Daily Journal)
          DailyJournalWidget(
            dailyStats: _dailyStats,
            initialDate: _focusedDate,
            seedColor: colorScheme.primary,
            dailyGoalMinutes: _dailyGoalMinutes,
            currentSeconds: _focusedDate.year == DateTime.now().year && 
                          _focusedDate.month == DateTime.now().month && 
                          _focusedDate.day == DateTime.now().day
                ? _secondsToday
                : (_dailyStats['${_focusedDate.year}-${_focusedDate.month.toString().padLeft(2, '0')}-${_focusedDate.day.toString().padLeft(2, '0')}']?.totalSeconds ?? 0),
            showHoursMode: _showHoursMode,
            onDateChanged: (date) {
              setState(() {
                _focusedDate = date;
                // Update statistics for the focused date
                if (date.year != _currentMonth.year || date.month != _currentMonth.month) {
                  _currentMonth = date;
                  _loadStatistics(showLoading: false);
                }
              });
            },
          ),
          
          const SizedBox(height: 16),
          
          // 3. Reading Activity (Heatmap)
          _buildHeatmap(context),
          
          const SizedBox(height: 32),

          // 4. Stats Overview Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Stats Overview',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 12),

          // 4. Stats Overview (Grid)
          _buildResponsiveGrid(context),
          
          const SizedBox(height: 24),
          
          // 4. Streak
          if (_showStreak && _currentStreak > 0)
            _buildStreakBadge(colorScheme),

          const SizedBox(height: 24),
          
          // 5. Challenges
          const ChallengeListWidget(),
          
          const SizedBox(height: 24),

          // 6. Personality Card
          const PersonalityCard(),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildTrendsView() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      key: const ValueKey('trends'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildTrendCard(
            title: 'Reading Rhythm',
            subtitle: 'Hourly Activity (Last 30 Days)',
            icon: Icons.access_time_filled_rounded,
            child: _buildHourlyBarChart(colorScheme),
          ),
          const SizedBox(height: 16),
          _buildTrendCard(
            title: 'Weekly Routine',
            subtitle: 'Average Reading Time per Day',
            icon: Icons.calendar_view_week_rounded,
            child: _buildDailyAverageChart(colorScheme),
          ),
          const SizedBox(height: 16),
          _buildTrendCard(
            title: 'Weekday vs. Weekend',
            subtitle: 'Comparison',
            icon: Icons.compare_arrows_rounded,
            child: _buildWeekdayVsWeekendStats(colorScheme),
          ),
          const SizedBox(height: 16),
          _buildTrendCard(
            title: 'Completion Funnel',
            subtitle: 'Library Progress',
            icon: Icons.filter_alt_rounded,
            child: _buildCompletionFunnel(colorScheme, textTheme),
          ),
          const SizedBox(height: 16),
          _buildTrendCard(
            title: 'Monthly Momentum',
            subtitle: 'Total Reading Time (Last 12 Months)',
            icon: Icons.show_chart_rounded,
            child: _buildMomentumLineChart(colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

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
              children: [
                Icon(icon, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    Text(subtitle, style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildStreakBadge(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary,
            colorScheme.primary.withOpacity(0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '🔥',
            style: TextStyle(fontSize: 24),
          ),
          const SizedBox(width: 8),
          Text(
            '$_currentStreak Day Streak!',
            style: TextStyle(
              color: colorScheme.onPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHourlyBarChart(ColorScheme colorScheme) {
    if (_hourlyActivity.isEmpty) return const Center(child: Text('No data available'));

    final maxSeconds = _hourlyActivity.values.fold(0, (max, val) => val > max ? val : max);
    if (maxSeconds == 0) return const Center(child: Text('No activity tracked yet'));

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxSeconds.toDouble() * 1.2,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              tooltipRoundedRadius: 8,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                 // Convert hour to AM/PM for tooltip
                final hour = group.x.toInt();
                final amPm = hour >= 12 ? 'PM' : 'AM';
                final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
                return BarTooltipItem(
                  '$h12 $amPm\n${(rod.toY / 60).round()} min',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  // Show label every 4 hours
                  if (value % 4 != 0) return const SizedBox.shrink();
                  final hour = value.toInt();
                  final amPm = hour >= 12 ? 'PM' : 'AM';
                  final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text('$h12$amPm', style: const TextStyle(fontSize: 10)),
                  );
                },
                reservedSize: 28,
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: _hourlyActivity.entries.map((e) {
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: e.value.toDouble(),
                  color: colorScheme.primary,
                  width: 8,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildDailyAverageChart(ColorScheme colorScheme) {
    if (_weekdayActivity.isEmpty) return const Center(child: Text('No data available'));

    // Find most active day
    int maxDaySeconds = -1;
    int mostActiveDay = 1; // 1 = Monday

    // Ensure we have data for all days (1-7)
    final Map<int, int> fullWeekData = {};
    for (int i = 1; i <= 7; i++) {
      fullWeekData[i] = _weekdayActivity[i] ?? 0;
      if (fullWeekData[i]! > maxDaySeconds) {
        maxDaySeconds = fullWeekData[i]!;
        mostActiveDay = i;
      }
    }
    
    // Day names
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final shortDays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final bestDayName = days[mostActiveDay - 1];

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.star_rounded,
                  color: colorScheme.onPrimaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Most Active Day',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    bestDayName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Weekly Bar Chart
        SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxDaySeconds == 0 ? 100 : maxDaySeconds.toDouble() * 1.15,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  tooltipRoundedRadius: 8,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final dayIndex = group.x.toInt() - 1;
                    final dayName = days[dayIndex];
                    return BarTooltipItem(
                      '$dayName\n${(rod.toY / 60).round()} min',
                      const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                       final index = value.toInt() - 1;
                       if (index < 0 || index >= 7) return const SizedBox.shrink();
                       return Padding(
                         padding: const EdgeInsets.only(top: 8.0),
                         child: Text(
                           shortDays[index], 
                           style: TextStyle(
                             fontSize: 12, 
                             fontWeight: value.toInt() == mostActiveDay ? FontWeight.bold : FontWeight.normal,
                             color: value.toInt() == mostActiveDay ? colorScheme.primary : colorScheme.onSurface,
                           )
                         ),
                       );
                    },
                    reservedSize: 28,
                  ),
                ),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(7, (index) {
                final dayNum = index + 1;
                final value = fullWeekData[dayNum]!.toDouble();
                final isMax = dayNum == mostActiveDay;
                return BarChartGroupData(
                  x: dayNum,
                  barRods: [
                    BarChartRodData(
                      toY: value,
                      color: isMax ? colorScheme.primary : colorScheme.surfaceContainerHighest,
                      width: 16,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: maxDaySeconds == 0 ? 100 : maxDaySeconds.toDouble() * 1.15,
                        color: Colors.transparent,
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeekdayVsWeekendStats(ColorScheme colorScheme) {
    if (_weekdayActivity.isEmpty) return const Center(child: Text('No data available'));

    // Separate Mon-Fri and Sat-Sun
    int weekdaySeconds = 0;
    int weekendSeconds = 0;
    
    _weekdayActivity.forEach((day, seconds) {
      if (day <= 5) weekdaySeconds += seconds;
      else weekendSeconds += seconds;
    });

    // Averages (avoid division by zero)
    double weekdayAvg = weekdaySeconds / 5 / 60; // Minutes
    double weekendAvg = weekendSeconds / 2 / 60; // Minutes
    
    final maxVal = weekdayAvg > weekendAvg ? weekdayAvg : weekendAvg;
    // Prevent division by zero if max is 0
    final displayMax = maxVal == 0 ? 1.0 : maxVal;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildComparisonBar('Weekdays', weekdayAvg, displayMax, colorScheme.primary),
          _buildComparisonBar('Weekends', weekendAvg, displayMax, colorScheme.secondary),
        ],
      ),
    );
  }

  Widget _buildComparisonBar(String label, double value, double max, Color color) {
    return Column(
      children: [
        Text('${value.round()}m', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          width: 60,
          height: 120,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.bottomCenter,
          child: AnimatedContainer(
            duration: const Duration(seconds: 1),
            width: 60,
            height: max == 0 ? 0 : (value / max) * 120,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildHeatmap(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    // Convert _dailyStats to heatmap format
    final datasets = <DateTime, int>{};
    _dailyStats.forEach((dateStr, stats) {
      if (stats.totalSeconds > 0) {
        final dateParts = dateStr.split('-');
        final date = DateTime(
          int.parse(dateParts[0]),
          int.parse(dateParts[1]),
          int.parse(dateParts[2]),
        );
        // Level based on reading time (e.g., 0-4)
        int level = (stats.totalSeconds / 60 / 15).floor().clamp(1, 4);
        datasets[date] = level;
      }
    });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.primary.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.grid_on_rounded, color: colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Reading Activity',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          HeatMap(
            datasets: datasets,
            colorMode: ColorMode.color,
            defaultColor: colorScheme.surfaceVariant.withOpacity(0.3),
            textColor: colorScheme.onSurface,
            showColorTip: false,
            showText: false,
            scrollable: true,
            size: 20,
            colorsets: {
              1: colorScheme.primary.withOpacity(0.2),
              2: colorScheme.primary.withOpacity(0.4),
              3: colorScheme.primary.withOpacity(0.7),
              4: colorScheme.primary,
            },
            onClick: (DateTime date) {
              setState(() {
                _focusedDate = date;
                // Reload specific stats if we jump months in the future/past
                if (date.year != _currentMonth.year || date.month != _currentMonth.month) {
                  _currentMonth = date;
                }
              });
            },
          ),
          const SizedBox(height: 8),
          Text(
             'Tap any date to view that day\'s reading progress. Use arrows to navigate across months.',
             style: Theme.of(context).textTheme.labelSmall?.copyWith(
               color: colorScheme.onSurfaceVariant,
               fontStyle: FontStyle.italic,
             ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveGrid(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;

    // Use 2 columns for portrait/narrow, 4 for landscape/wide
    int crossAxisCount = screenWidth > 600 ? 4 : 2;
    // Tighter aspect ratio to prevent cards from being too tall
    double childAspectRatio = screenWidth > 600 ? 1.4 : 1.25;

    return GridView.count(
      crossAxisCount: crossAxisCount,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: childAspectRatio,
      children: [
        StatCard(
          label: 'Today',
          value: _formatDuration(_secondsToday),
          unit: _formatDuration(_secondsToday).contains('h') ? null : 'minutes',
          icon: Icons.today_rounded,
          iconColor: colorScheme.primary,
        ),
        StatCard(
          label: 'This Week',
          value: _formatDuration(_minutesThisWeek * 60),
          unit: _formatDuration(_minutesThisWeek * 60).contains('h') ? null : 'minutes',
          icon: Icons.date_range_rounded,
          iconColor: colorScheme.primary,
        ),
        StatCard(
          label: 'This Month',
          value: _formatDuration(_minutesThisMonth * 60),
          unit: _formatDuration(_minutesThisMonth * 60).contains('h') ? null : 'minutes',
          icon: Icons.calendar_month_rounded,
          iconColor: colorScheme.primary,
        ),
        StatCard(
          label: 'Avg Session',
          value: _formatDuration((_avgSessionTime * 60).toInt()),
          unit: _formatDuration((_avgSessionTime * 60).toInt()).contains('h') ? null : 'minutes',
          icon: Icons.speed_rounded,
          iconColor: colorScheme.primary,
        ),
      ],
    );
  }

  Widget _buildCompletionFunnel(ColorScheme colorScheme, TextTheme textTheme) {
    final int total = _completionFunnel['total'] ?? 0;
    final int started = _completionFunnel['started'] ?? 0;
    final int completed = _completionFunnel['completed'] ?? 0;

    return Column(
      children: [
        _buildFunnelRow('Total Library', total, Icons.library_books_rounded, colorScheme.primary),
        const Icon(Icons.arrow_drop_down, color: Colors.grey),
        _buildFunnelRow('Active / Reading', started, Icons.play_circle_filled_rounded, colorScheme.secondary),
        const Icon(Icons.arrow_drop_down, color: Colors.grey),
        _buildFunnelRow('Finished', completed, Icons.check_circle_rounded, colorScheme.tertiary),
      ],
    );
  }

  Widget _buildFunnelRow(String label, int count, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('$count', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildMomentumLineChart(ColorScheme colorScheme) {
    // Generate last 12 months keys
    final now = DateTime.now();
    final List<String> last12Months = [];
    for (int i = 11; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      last12Months.add('${d.year}-${d.month.toString().padLeft(2, '0')}');
    }

    final double maxMins = last12Months.fold(0.0, (max, monthKey) {
      final val = (_monthlyMomentum[monthKey] ?? 0) / 60.0;
      return val > max ? val : max;
    });

    final displayMax = maxMins == 0 ? 100.0 : maxMins * 1.2;

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= 12) return const SizedBox.shrink();
                  // Show label every 2 months to avoid clutter
                  if (index % 2 != 0) return const SizedBox.shrink(); 
                  
                  final monthKey = last12Months[index];
                  final monthParts = monthKey.split('-');
                  final monthInt = int.parse(monthParts[1]);
                  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(months[monthInt - 1], style: const TextStyle(fontSize: 10)),
                  );
                },
                reservedSize: 22,
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: 11,
          minY: 0,
          maxY: displayMax,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              tooltipRoundedRadius: 8,
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((LineBarSpot touchedSpot) {
                  return LineTooltipItem(
                    '${touchedSpot.y.toStringAsFixed(1)} m',
                    const TextStyle(
                      color: Colors.white, 
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(12, (i) {
                final monthKey = last12Months[i];
                final minutes = (_monthlyMomentum[monthKey] ?? 0) / 60.0;
                return FlSpot(i.toDouble(), minutes);
              }),
              isCurved: true,
              curveSmoothness: 0.35,
              color: colorScheme.primary,
              barWidth: 4,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: colorScheme.primary.withOpacity(0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int totalSeconds) {
    int totalMinutes = totalSeconds ~/ 60;
    
    if (!_showHoursMode || totalMinutes < 60) {
      return '$totalMinutes';
    }
    
    int hours = totalMinutes ~/ 60;
    int minutes = totalMinutes % 60;
    
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }

  Widget _buildToggleButton({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return const SizedBox.shrink(); 
  }
}
