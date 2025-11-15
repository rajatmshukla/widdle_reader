import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sleep_timer_provider.dart';

class CountdownTimerWidget extends StatelessWidget {
  final double size;
  final bool showIcon;
  final VoidCallback? onTap;

  const CountdownTimerWidget({
    super.key,
    this.size = 24.0, 
    this.showIcon = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<SleepTimerProvider>(
      builder: (context, timerProvider, child) {
        // If timer is not active and we should show icon
        if (!timerProvider.isActive && showIcon) {
          return Icon(
            Icons.bedtime_outlined,
            size: size,
            color: Theme.of(context).colorScheme.onSurface,
          );
        }
        
        // If timer is not active and we shouldn't show icon
        if (!timerProvider.isActive) {
          return const SizedBox.shrink();
        }
        
        // Calculate progress value (1.0 to 0.0)
        final totalSeconds = timerProvider.totalDuration?.inSeconds ?? 1;
        final remainingSeconds = timerProvider.remainingTime?.inSeconds ?? 0;
        final progress = remainingSeconds / totalSeconds;
        
        final colorScheme = Theme.of(context).colorScheme;
        
        // For small size, make it more icon-like
        if (size <= 28) {
          return SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Circular progress indicator
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: size * 0.1,
                  backgroundColor: Colors.transparent,
                  color: colorScheme.primary,
                ),
                // Small moon icon
                Icon(
                  Icons.nightlight_round,
                  size: size * 0.5,
                  color: colorScheme.primary,
                ),
              ],
            ),
          );
        }
        
        return GestureDetector(
          onTap: onTap != null ? onTap : null,
          child: Container(
            width: size,
            height: size,
            margin: EdgeInsets.all(size * 0.25),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Circular progress indicator
                SizedBox(
                  width: size,
                  height: size,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: size * 0.1,
                    backgroundColor: colorScheme.surfaceVariant.withOpacity(0.3),
                    color: colorScheme.primary,
                  ),
                ),
                
                // Text showing remaining minutes (only when size > 30)
                if (size > 30)
                  Text(
                    '${timerProvider.remainingTime?.inMinutes ?? 0}',
                    style: TextStyle(
                      fontSize: size * 0.4,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onBackground,
                    ),
                  ),
                
                // Small moon icon (only when size <= 30)
                if (size <= 30)
                  Icon(
                    Icons.nightlight_round,
                    size: size * 0.4,
                    color: colorScheme.primary,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
} 