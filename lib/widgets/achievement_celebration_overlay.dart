import 'package:flutter/material.dart';
import 'dart:async';
import '../models/achievement.dart';
import '../services/achievement_service.dart';

/// Global overlay for showing achievement unlock celebrations
class AchievementCelebrationOverlay extends StatefulWidget {
  final Widget child;
  
  const AchievementCelebrationOverlay({
    super.key,
    required this.child,
  });

  @override
  State<AchievementCelebrationOverlay> createState() => _AchievementCelebrationOverlayState();
}

class _AchievementCelebrationOverlayState extends State<AchievementCelebrationOverlay> {
  final AchievementService _achievementService = AchievementService();
  StreamSubscription<Achievement>? _unlockSubscription;
  final List<Achievement> _pendingCelebrations = [];
  bool _isShowingCelebration = false;

  @override
  void initState() {
    super.initState();
    _unlockSubscription = _achievementService.unlockStream.listen(_onAchievementUnlocked);
  }

  @override
  void dispose() {
    _unlockSubscription?.cancel();
    super.dispose();
  }

  void _onAchievementUnlocked(Achievement achievement) {
    _pendingCelebrations.add(achievement);
    _showNextCelebration();
  }

  void _showNextCelebration() {
    if (_isShowingCelebration || _pendingCelebrations.isEmpty) return;
    
    _isShowingCelebration = true;
    final achievement = _pendingCelebrations.removeAt(0);
    
    // Show snackbar celebration
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AchievementSnackContent(achievement: achievement),
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.transparent,
            elevation: 0,
            margin: const EdgeInsets.all(16),
            padding: EdgeInsets.zero,
          ),
        ).closed.then((_) {
          _isShowingCelebration = false;
          _showNextCelebration();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Content widget for achievement snackbar
class AchievementSnackContent extends StatelessWidget {
  final Achievement achievement;
  
  const AchievementSnackContent({
    super.key,
    required this.achievement,
  });

  int _getXPForTier(AchievementTier tier) {
    switch (tier) {
      case AchievementTier.bronze: return 10;
      case AchievementTier.silver: return 25;
      case AchievementTier.gold: return 50;
      case AchievementTier.platinum: return 100;
      case AchievementTier.diamond: return 250;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final xp = _getXPForTier(achievement.tier);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer,
            colorScheme.primary.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Achievement icon with glow
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: achievement.tierColor.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(
                color: achievement.tierColor,
                width: 2,
              ),
            ),
            child: Icon(
              achievement.icon,
              color: achievement.tierColor,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          // Achievement info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '🏆 Achievement Unlocked!',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  achievement.name,
                  style: TextStyle(
                    color: colorScheme.onPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  achievement.description,
                  style: TextStyle(
                    color: colorScheme.onPrimary.withOpacity(0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // XP badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '+$xp XP',
              style: TextStyle(
                color: colorScheme.onPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
