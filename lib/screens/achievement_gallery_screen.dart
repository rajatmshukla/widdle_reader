import 'package:flutter/material.dart';
import '../models/achievement.dart';
import '../services/achievement_service.dart';
import '../widgets/achievement_badge.dart';

/// Screen displaying all achievements in a gallery view
class AchievementGalleryScreen extends StatefulWidget {
  const AchievementGalleryScreen({super.key});

  @override
  State<AchievementGalleryScreen> createState() => _AchievementGalleryScreenState();
}

class _AchievementGalleryScreenState extends State<AchievementGalleryScreen>
    with SingleTickerProviderStateMixin {
  final AchievementService _achievementService = AchievementService();
  late TabController _tabController;
  Map<AchievementCategory, List<Achievement>> _achievementsByCategory = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: AchievementCategory.values.length,
      vsync: this,
    );
    _loadAchievements();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAchievements() async {
    final byCategory = await _achievementService.getAchievementsByCategory();
    if (mounted) {
      setState(() {
        _achievementsByCategory = byCategory;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Achievements'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: AchievementCategory.values.map((category) {
            return Tab(
              icon: Icon(category.icon),
              text: category.displayName,
            );
          }).toList(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Progress summary
                _buildProgressSummary(colorScheme, textTheme),
                // Achievement tabs
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: AchievementCategory.values.map((category) {
                      return _buildCategoryGrid(category);
                    }).toList(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildProgressSummary(ColorScheme colorScheme, TextTheme textTheme) {
    final unlocked = _achievementService.unlockedCount;
    final total = _achievementService.totalCount;
    final progress = total > 0 ? unlocked / total : 0.0;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Progress ring
          SizedBox(
            width: 60,
            height: 60,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 6,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                ),
                Text(
                  '${(progress * 100).round()}%',
                  style: textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Stats
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$unlocked of $total Achievements',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Keep reading to unlock more!',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Trophy icon
          Icon(
            Icons.emoji_events,
            size: 40,
            color: colorScheme.primary.withOpacity(0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryGrid(AchievementCategory category) {
    final achievements = _achievementsByCategory[category] ?? [];

    if (achievements.isEmpty) {
      return Center(
        child: Text('No achievements in this category'),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.8,
      ),
      itemCount: achievements.length,
      itemBuilder: (context, index) {
        final achievement = achievements[index];
        return AchievementBadge(
          achievement: achievement,
          size: 70,
          showLabel: true,
          onTap: () => _showAchievementDetails(achievement),
        );
      },
    );
  }

  void _showAchievementDetails(Achievement achievement) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              // Badge
              AchievementBadge(
                achievement: achievement,
                size: 100,
                showLabel: false,
              ),
              const SizedBox(height: 16),
              // Name
              Text(
                achievement.isUnlocked || !achievement.isSecret
                    ? achievement.name
                    : '???',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              // Description
              Text(
                achievement.isUnlocked || !achievement.isSecret
                    ? achievement.description
                    : 'This achievement is secret. Keep reading to discover it!',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              // Tier and status
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: achievement.tierColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      achievement.tier.displayName,
                      style: textTheme.labelMedium?.copyWith(
                        color: achievement.tierColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: achievement.isUnlocked
                          ? Colors.green.withOpacity(0.2)
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      achievement.isUnlocked ? 'Unlocked' : 'Locked',
                      style: textTheme.labelMedium?.copyWith(
                        color: achievement.isUnlocked
                            ? Colors.green
                            : colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              // Unlock date
              if (achievement.isUnlocked && achievement.unlockedAt != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Unlocked on ${_formatDate(achievement.unlockedAt!)}',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              // Progress bar for locked achievements
              if (!achievement.isUnlocked && achievement.targetValue != null) ...[
                const SizedBox(height: 16),
                FutureBuilder<double>(
                  future: _achievementService.getProgress(achievement.id),
                  builder: (context, snapshot) {
                    final progress = snapshot.data ?? 0.0;
                    return Column(
                      children: [
                        LinearProgressIndicator(
                          value: progress,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${(progress * 100).round()}% complete',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
