# Widdle Reader v1.0.5-alpha Release Notes

**Release Date**: January 2025  
**Version**: 1.0.5-alpha+7  
**Build Type**: Alpha Release

## 🐛 Bug Fixes

### Backup & Restore
- **Fixed FilePicker Error**: Resolved PlatformException when restoring audiobook progress from backup on Android
  - Changed from `FileType.custom` with `allowedExtensions: ['json']` to `FileType.any`
  - Users can now successfully restore their backup files without errors

### Persistent Sorting Preferences
- **Fixed Library Sorting**: Library and tag screen sorting preferences are now persistent
  - Sort options are remembered between app sessions
  - No more resetting to default sort order when reopening the app

## ✨ New Features & Improvements

### Enhanced Bookmark System
- **Smart Default Names**: Bookmarks now have intelligent default names
  - Format: `"Book Title - Chapter Name - Position"` for multi-chapter books
  - Format: `"Book Title - Position"` for single-chapter books
  - Example: `"Jeremy Clarkson - Chapter 3: The Great Adventure - 1:23:45"`

- **Improved User Experience**: 
  - No need to erase default text when creating bookmarks
  - Default name appears as placeholder text
  - Users can immediately start typing to override default name
  - Leave empty to use comprehensive default name with full context

### Chapter Integration
- **Complete Position Context**: Bookmarks now capture and display:
  - Book title for identification
  - Chapter name for multi-chapter audiobooks
  - Exact timestamp position within the chapter
  - Full context for easy navigation back to specific moments

## 🔧 Technical Improvements

- **State Management**: Enhanced persistent storage for user preferences
- **Error Handling**: Improved file picker compatibility across Android devices
- **User Interface**: Streamlined bookmark creation workflow

## 📱 Compatibility

- **Android**: Minimum SDK 21 (Android 5.0+)
- **Target SDK**: 35 (Android 15)
- **Flutter**: SDK 3.7.2+

## 🚀 Installation

This is an alpha release. Install the provided APK file to test the new features and bug fixes.

## 📝 Notes

This alpha release focuses on fixing critical user-reported issues and improving the bookmark system for better audiobook navigation. The enhanced bookmark naming system provides comprehensive context, making it easier to organize and return to specific moments in your audiobooks.

---

**Feedback**: Please report any issues or suggestions for this alpha release. 