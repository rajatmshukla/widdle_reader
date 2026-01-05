import 'package:flutter/material.dart';
import 'package:provider/provider.dart' as provider;
import '../services/personality_service.dart';
import '../providers/audiobook_provider.dart';

/// Beautiful card displaying reading personality profile
class PersonalityCard extends StatefulWidget {
  const PersonalityCard({super.key});

  @override
  State<PersonalityCard> createState() => _PersonalityCardState();
}

class _PersonalityCardState extends State<PersonalityCard>
    with SingleTickerProviderStateMixin {
  final PersonalityService _personalityService = PersonalityService();
  ReadingPersonality? _personality;
  bool _isLoading = true;
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _loadPersonality();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> _loadPersonality() async {
    if (!mounted) return;
    
    // Get tags from provider for better analysis
    final audiobookProvider = provider.Provider.of<AudiobookProvider>(context, listen: false);
    final bookTags = <String, Set<String>>{};
    for (var book in audiobookProvider.audiobooks) {
      bookTags[book.id] = book.tags;
    }

    final personality = await _personalityService.analyzePersonality(bookTags: bookTags);
    if (mounted) {
      setState(() {
        _personality = personality;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Get text scaling factor for accessibility responsiveness
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);

    if (_isLoading) {
      return _buildLoadingCard(colorScheme);
    }

    if (_personality == null || _personality!.isEmpty) {
      return _buildEmptyCard(colorScheme, textTheme);
    }

    final type = _personality!.type;
    // Use theme's primary color as the base for the card to ensure it follows the seed color
    final primaryColor = colorScheme.primary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primaryColor,
            primaryColor.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, // Vital for responsiveness
          children: [
            // Header row
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    type.icon,
                    color: Colors.white,
                    size: 28 * textScale.clamp(1.0, 1.5),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reading Personality',
                        style: textTheme.labelMedium?.copyWith(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: (textTheme.labelMedium?.fontSize ?? 12) * textScale.clamp(1.0, 1.2),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        type.name,
                        style: textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: (textTheme.headlineSmall?.fontSize ?? 24) * textScale.clamp(1.0, 1.3),
                        ),
                        softWrap: true,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Description
            Text(
              type.description,
              style: textTheme.bodyMedium?.copyWith(
                color: Colors.white.withOpacity(0.95),
                height: 1.3,
                fontSize: (textTheme.bodyMedium?.fontSize ?? 14) * textScale.clamp(1.0, 1.25),
              ),
              softWrap: true,
            ),
            const SizedBox(height: 20),
            
            // Stats Grid - Using Wrap for large font support
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.spaceEvenly,
                children: [
                  _buildFlexStat(
                    icon: _personality!.timePreference.icon,
                    label: _personality!.timePreference.name,
                    textTheme: textTheme,
                    textScale: textScale,
                  ),
                  _buildFlexStat(
                    icon: Icons.timer,
                    label: '${_personality!.avgSessionMinutes.round()}m avg',
                    textTheme: textTheme,
                    textScale: textScale,
                  ),
                  _buildFlexStat(
                    icon: Icons.trending_up,
                    label: '${_personality!.consistencyScore.round()}% consistent',
                    textTheme: textTheme,
                    textScale: textScale,
                  ),
                  if (_personality!.stabilityScore > 0)
                    _buildFlexStat(
                      icon: Icons.repeat,
                      label: '${_personality!.stabilityScore.round()}% routine',
                      textTheme: textTheme,
                      textScale: textScale,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlexStat({
    required IconData icon,
    required String label,
    required TextTheme textTheme,
    required double textScale,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.white, size: 20 * textScale.clamp(1.0, 1.4)),
        const SizedBox(height: 4),
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: Colors.white.withOpacity(0.95),
            fontWeight: FontWeight.w500,
            fontSize: (textTheme.labelSmall?.fontSize ?? 11) * textScale.clamp(1.0, 1.3),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildLoadingCard(ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 180,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Center(
        child: CircularProgressIndicator(
          color: colorScheme.primary,
          strokeWidth: 3,
        ),
      ),
    );
  }

  Widget _buildEmptyCard(ColorScheme colorScheme, TextTheme textTheme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.psychology_alt_rounded,
            size: 48,
            color: colorScheme.primary.withOpacity(0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'Uncover Your Reading Identity',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Keep listening to audiobooks to generate your unique personality profile!',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
