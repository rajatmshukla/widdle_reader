# Changelog

## 1.0.3 - Current Release

### Enhanced
- Improved cover image priority system: Now prioritizes embedded metadata first, then any image file in folder
- Added tag rename functionality alongside existing tag delete feature
- Enhanced UI: Converted bottom sheet menus to dialogs for better user experience
- Improved tag creation flow with textbox-first design

### Added
- Bulletproof Favorites tag system that cannot be deleted or renamed
- Comprehensive data management: Tags, favorites, and all progress data now included in backup/restore
- Enhanced backup system with automatic corruption detection and recovery
- Data health monitoring with tag statistics in Settings

### Fixed
- Cover art now properly prioritizes embedded audio file metadata over folder images
- Tag system maintains full data consistency during rename operations
- Favorites tag guaranteed to always exist with multiple fallback mechanisms

## 1.0.2 - May 26, 2024

### Fixed
- Fixed "Reset Progress" functionality to properly update UI elements
- Progress bar and shading now correctly reset to 0% when progress is reset
- Improved caching mechanisms to prevent stale data persistence

### Improved
- Enhanced app bar icons using seedColor for better visibility
- Increased icon size for improved accessibility
- Removed redundant "Tap here" guide button from empty library view
- Added better user feedback with status messages during reset process

## 1.0.1 - May 16, 2024

### Added
- Initial release with core audiobook playback functionality
- Library management for audiobook collection
- Progress tracking and bookmarking
- Sleep timer functionality
- Theme customization options 