import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart' as provider;
import '../services/statistics_service.dart';
import '../providers/theme_provider.dart';
import '../widgets/app_logo.dart';
import '../widgets/progress_ring_widget.dart';
import '../widgets/reading_timeline_widget.dart';
import '../widgets/enhanced_heatmap_widget.dart';
import '../widgets/stat_card.dart';
import '../models/reading_statistics.dart';
import '../models/reading_session.dart';
import '../theme.dart';
import 'achievement_gallery_screen.dart';
import '../widgets/personality_card.dart';
import '../widgets/challenge_list_widget.dart';

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
  List<ReadingSession> _recentSessions = [];
  bool _loading = true;
  
  // Default daily goal (30 minutes)
  int _dailyGoalMinutes = 30;
  bool _showStreak = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStatistics();
    
    // Listen for real-time updates
    _statsSubscription = _statsService.onStatsUpdated.listen((_) {
      if (mounted) {
        debugPrint('📊 Received real-time stats update');
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
      _minutesThisWeek = await _statsService.getTotalMinutesThisWeek();
      _minutesThisMonth = await _statsService.getTotalMinutesThisMonth();
      _sessionsThisWeek = await _statsService.getTotalSessionsThisWeek();
      
      // Get today's minutes
      final today = DateTime.now();
      final todayString = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final todayStats = await _statsService.getDailyStats(todayString);
      _secondsToday = todayStats.totalSeconds;
      
      // Load recent sessions
      _recentSessions = await _statsService.getRecentSessions(20);
      
      debugPrint('📊 Loaded ${_recentSessions.length} recent sessions');
    } catch (e) {
      debugPrint('Error loading statistics: $e');
    }

    if (mounted) {
      setState(() => _loading = false);
    }
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

  Future<void> _showSettingsDialog() async {
    int tempGoal = _dailyGoalMinutes;
    bool tempShowStreak = _showStreak;

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

  Widget _buildDayDetailsSheet(String dateString, DailyStats stats) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          _buildStatRow(Icons.timer_outlined, 'Total Reading Time',
              '${stats.totalMinutes} minutes', colorScheme, textTheme),
          const SizedBox(height: 12),
          _buildStatRow(Icons.auto_stories_rounded, 'Sessions',
              '${stats.sessionCount}', colorScheme, textTheme),
          const SizedBox(height: 12),
          _buildStatRow(Icons.library_books_rounded, 'Books',
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
            const Text('Reading Journey'),
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
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Hero Progress Ring
                      ProgressRingWidget(
                        currentSeconds: _secondsToday,
                        targetMinutes: _dailyGoalMinutes,
                        metricLabel: 'Today',
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Streak indicator
                      if (_showStreak && _currentStreak > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.orange.shade400,
                                Colors.deepOrange.shade600,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.orange.withAlpha(76),
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
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      
                      const SizedBox(height: 24),
                      
                      // Personality Card
                      const PersonalityCard(),
                      
                      const SizedBox(height: 24),
                      
                      // Weekly Challenges
                      const ChallengeListWidget(),
                      
                      const SizedBox(height: 32),
                      
                      // Reading Timeline
                      ReadingTimelineWidget(
                        sessions: _recentSessions,
                        selectedDate: DateTime.now(),
                      ),
                      
                      const SizedBox(height: 32),
                      
                      // Stats Grid
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.3,
                        children: [
                          StatCard(
                            label: 'This Week',
                            value: '$_minutesThisWeek',
                            unit: 'minutes',
                            icon: Icons.calendar_view_week_rounded,
                            iconColor: Colors.blue,
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
                            iconColor: Colors.purple,
                          ),
                          StatCard(
                            label: 'This Month',
                            value: '$_minutesThisMonth',
                            unit: 'minutes',
                            icon: Icons.calendar_month_rounded,
                            iconColor: Colors.green,
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 32),
                      
                      // Enhanced Heatmap
                      EnhancedHeatmapWidget(
                        dailyStats: _dailyStats,
                        currentMonth: _currentMonth,
                        onMonthChanged: _onMonthChanged,
                        onDayTapped: _onDayTapped,
                        seedColor: colorScheme.primary,
                      ),
                      
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
