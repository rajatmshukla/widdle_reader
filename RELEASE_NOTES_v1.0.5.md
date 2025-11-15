# Widdle Reader v1.0.5 Release Notes

## What's New in This Update

• **Smart Auto-Tag System**: Enhanced tag creation with intelligent duplicate prevention and series consolidation - no more multiple similar tags like "Fantasy" and "Fantasy Series"

• **Scan Existing Library**: New feature to create tags from your existing audiobooks' folder structure - perfect for recovering deleted tags or organizing books from previous app versions

• **Improved Loading Experience**: Replaced full-screen loading with a sleek, non-blocking progress card that lets you see your library while books are being added

---

## Detailed Features

### 🏷️ Enhanced Auto-Tag System
- **Intelligent Duplicate Prevention**: Advanced similarity detection prevents creating near-identical tags
- **Series Consolidation**: Automatically recognizes and consolidates series variations (e.g., "Harry Potter 1", "Harry Potter Book 2" → "Harry Potter")
- **Smart Tag Suggestions**: Analyzes folder structure to suggest meaningful tags for better organization

### 📚 Scan Existing Library for Tags
- **Two Access Points**: Available from main screen (+ button) and Settings > Data Management
- **Folder Structure Analysis**: Intelligently groups books and creates tags based on their directory structure  
- **Perfect for Upgrades**: Users from previous app versions can scan their library to get organized tags
- **Tag Recovery**: Restore accidentally deleted tags by re-analyzing your audiobook folders

### 🎯 Seamless User Experience
- **Non-Blocking Loading**: New card-based progress indicator at the top of the screen
- **Real-Time Feedback**: See progress and results with animated transitions
- **Better Performance**: Optimized for release builds with multiple safety mechanisms
- **Enhanced Feedback**: Clear success messages with option to view newly created tags

### 🔧 Technical Improvements
- **Robust State Management**: Enhanced loading state handling for better reliability
- **Smart Root Path Detection**: Groups books by common folder structures for better tag organization
- **Comprehensive Error Handling**: Better error messages and recovery mechanisms
- **Persistent Sort Preferences**: Your sorting choices are now remembered between app sessions

---

## For Developers

### New Methods Added
- `scanExistingLibraryForTags()` - Scans existing audiobooks and creates auto-tags
- `_findCommonRootPaths()` - Intelligently groups books by folder structure
- Enhanced duplicate detection with Levenshtein distance algorithm
- Smart series consolidation with 95% similarity threshold

### UI/UX Improvements
- Replaced `DetailedLoadingWidget` with animated card-based loading
- Added "Library Actions" dialog with scan library option
- Enhanced Settings screen with scan library feature in Data Management

---

## Installation

This is a standard app update. Simply install the new version and your existing library, bookmarks, and preferences will be preserved.

## Feedback

We'd love to hear about your experience with the new auto-tag features! Please share your feedback and any suggestions for improvement.

---

**Version**: 1.0.5+6  
**Build Date**: December 2024  
**Compatibility**: Android 7.0+ (API level 24+) 