import 'package:flutter/material.dart';
import '../services/achievement_service.dart';

/// A badge widget showing user's total XP in the app bar
class XPBadge extends StatefulWidget {
  const XPBadge({super.key});

  @override
  State<XPBadge> createState() => _XPBadgeState();
}

class _XPBadgeState extends State<XPBadge> {
  final AchievementService _achievementService = AchievementService();
  int _totalXP = 0;

  @override
  void initState() {
    super.initState();
    _loadXP();
    
    // Listen for new achievement unlocks to update XP
    _achievementService.unlockStream.listen((_) {
      _loadXP();
    });
  }

  Future<void> _loadXP() async {
    await _achievementService.initialize();
    if (mounted) {
      setState(() {
        _totalXP = _achievementService.getTotalXP();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.star_rounded,
            size: 18,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Text(
            '$_totalXP XP',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
