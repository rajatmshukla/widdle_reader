import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audiobook_provider.dart';

class DetailedLoadingWidget extends StatefulWidget {
  const DetailedLoadingWidget({super.key});

  @override
  State<DetailedLoadingWidget> createState() => _DetailedLoadingWidgetState();
}

class _DetailedLoadingWidgetState extends State<DetailedLoadingWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<double>(
      begin: -1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Consumer<AudiobookProvider>(
      builder: (context, provider, child) {
        // Animate in when loading starts, animate out when loading stops
        if (provider.isLoading) {
          _animationController.forward();
        } else {
          _animationController.reverse();
        }

        return AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            if (_animationController.value == 0.0 && !provider.isLoading) {
              return const SizedBox.shrink();
            }

            return Transform.translate(
              offset: Offset(0, _slideAnimation.value * 100),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.primary.withOpacity(0.3),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Loading Audiobooks...',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      if (provider.isLoading)
                        Icon(
                          Icons.schedule,
                          size: 16,
                          color: colorScheme.primary.withOpacity(0.7),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
} 