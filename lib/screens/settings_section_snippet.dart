  // Notification Settings Section
  Widget _buildNotificationSection(
    TextTheme textTheme,
    ColorScheme colorScheme,
  ) {
    return FutureBuilder<bool>(
      future: _storageService.getNotificationsEnabled(),
      builder: (context, snapshot) {
        final enabled = snapshot.data ?? true;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              'Notifications',
              Icons.notifications_active_outlined,
              textTheme,
              colorScheme,
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: SwitchListTile(
                title: Text(
                  'Daily Reminders',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Get fun reminders to keep your streak alive',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                value: enabled,
                onChanged: (value) async {
                  await _storageService.setNotificationsEnabled(value);
                  setState(() {});
                  
                  if (value) {
                    // Re-schedule if enabled
                    final engagementManager = EngagementManager();
                    await engagementManager.initialize();
                  } else {
                    // Cancel if disabled
                    final notificationService = NotificationService();
                    await notificationService.cancelAll();
                  }
                },
                secondary: Icon(
                  enabled ? Icons.notifications_active : Icons.notifications_off,
                  color: enabled ? colorScheme.primary : colorScheme.outline,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
