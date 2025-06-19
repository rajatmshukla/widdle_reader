# Widdle Reader - Audiobook Player App

Widdle Reader is a feature-rich, modern audiobook player built with Flutter. The app provides a clean, intuitive interface for listening to audiobooks with support for background playback, media notifications, and progress tracking.

**Current Version: 1.0.4** (See [Changelog](./CHANGELOG.md) for details)

## Features

- **Robust Audiobook Library Management**: Advanced recursive folder scanning for any audiobook organization structure
- **Flexible Folder Structure Support**: Works with single books, series, and nested folder hierarchies
- **Background Playback**: Continue listening when the app is in the background
- **Media Controls**: Control playback from notifications and lockscreen
- **Progress Tracking**: Automatically saves your position in each audiobook
- **Theme Customization**: Light/dark mode with customizable seed colors
- **Responsive Design**: Optimized for both portrait and landscape orientations
- **Chapter Navigation**: Easy navigation between audiobook chapters
- **Sleep Timer**: Set a timer to automatically pause playback after a specified duration
- **Bookmarks**: Add and manage bookmarks at specific points in your audiobooks
- **Variable Playback Speed**: Adjust the playback speed from 0.5x to 2.0x
- **Enhanced Metadata Support**: Automatic extraction of titles, authors, and cover art with priority system
- **Advanced Tag System**: Create, rename, and organize custom tags with bulletproof Favorites protection
- **Comprehensive Data Management**: Complete backup/restore with corruption detection and recovery
- **Real-time Progress Display**: Visual indicators showing completion percentage
- **Data Health Monitoring**: Tag statistics and integrity checking in Settings

## Audiobook Organization

### Supported Folder Structures

Widdle Reader now supports **any folder structure** for your audiobooks! The app uses advanced recursive scanning to find audiobooks regardless of how they're organized.

#### Examples of Supported Structures:

**Single Books:**
```
My Audiobooks/
└── The Great Gatsby/
    ├── chapter1.m4a
    ├── chapter2.m4a
    ├── chapter3.m4a
    └── cover.jpg
```

**Book Series:**
```
My Audiobooks/
├── Harry Potter Series/
│   ├── Book 1 - Philosopher's Stone/
│   │   ├── chapter1.m4a
│   │   ├── chapter2.m4a
│   │   └── cover.jpg
│   ├── Book 2 - Chamber of Secrets/
│   │   ├── chapter1.m4a
│   │   ├── chapter2.m4a
│   │   └── cover.jpg
│   └── Book 3 - Prisoner of Azkaban/
│       ├── chapter1.m4a
│       └── cover.jpg
└── Lord of the Rings/
    ├── Fellowship of the Ring/
    │   ├── part1.m4b
    │   └── part2.m4b
    └── Two Towers/
        └── full_book.m4a
```

**Mixed Structure:**
```
Audiobooks/
├── Single Books/
│   ├── 1984/
│   │   └── 1984_full.m4b
│   └── Dune/
│       ├── part1.m4a
│       └── part2.m4a
├── Science Fiction Series/
│   └── Foundation Series/
│       ├── Foundation/
│       │   ├── ch1.mp3
│       │   └── ch2.mp3
│       └── Foundation and Empire/
│           └── full.m4a
└── Classics/
    └── Pride and Prejudice/
        ├── chapter1.mp3
        └── cover.png
```

### How to Add Audiobooks

1. **Scan for Books (Recommended)**: 
   - Select your root audiobooks folder
   - The app will recursively scan all subfolders
   - Automatically finds all audiobooks regardless of nesting level
   - Perfect for large, organized libraries

2. **Add Single Book**: 
   - Select a specific folder containing one audiobook
   - Useful for adding individual books

### Supported Audio Formats

- **MP3** (.mp3)
- **M4A** (.m4a) 
- **M4B** (.m4b) - Audiobook format
- **WAV** (.wav)
- **OGG** (.ogg)
- **AAC** (.aac)
- **FLAC** (.flac)

### Cover Art Support

The app automatically finds cover art using an intelligent priority system:
1. **Embedded metadata** in audio files (highest priority)
2. **Image files** in the audiobook folder (fallback):
   - `cover.jpg/png/webp`
   - `folder.jpg/png/webp`
   - `albumart.jpg/png/webp`
   - `front.jpg/png/webp`
   - `artwork.jpg/png/webp`

This ensures the best possible cover art display by prioritizing embedded metadata first, then falling back to folder images.

## Tech Stack

- **Flutter**: Cross-platform UI framework
- **Provider**: State management (migrating to Riverpod)
- **just_audio/just_audio_background**: Audio playback and background services
- **Path Provider/File Picker**: File system interaction
- **Shared Preferences**: Local data storage
- **flutter_media_metadata**: Advanced metadata extraction

## Architecture

The app follows a clean architecture pattern with separation of concerns:

### Directory Structure

```
lib/
├── main.dart          # App entry point
├── theme.dart         # Theme definitions
├── models/           # Data models
├── providers/        # State management
├── screens/          # UI screens
├── services/         # Business logic
├── utils/            # Utility functions
└── widgets/          # Reusable UI components
```

### Core Components

#### Models

- **Audiobook**: Represents an audiobook with metadata, chapters, and author information
- **Chapter**: Represents a chapter within an audiobook with playback info
- **Bookmark**: Stores user-created bookmarks for specific points in audiobooks
- **Tag**: Represents custom user tags with protection mechanisms for system tags

#### Services

- **SimpleAudioService**: Core audio playback functionality
- **AudioHandler**: Manages media session interactions and notifications
- **StorageService**: Handles saving/loading progress and preferences with in-memory caching
- **MetadataService**: Enhanced metadata extraction with recursive folder scanning

#### Providers (State Management)

- **AudiobookProvider**: Manages the audiobook library and playback state
- **ThemeProvider**: Handles theme preferences and customization
- **SleepTimerProvider**: Manages the sleep timer functionality
- **TagProvider**: Handles tag creation, deletion, renaming, and system tag protection

#### Screens

- **SplashScreen**: Initial loading screen
- **LibraryScreen**: Main audiobook collection view
- **SimplePlayerScreen**: Audiobook playback interface
- **SettingsScreen**: App configuration options
- **BookmarksScreen**: View and manage audiobook bookmarks

#### Widgets

- **AppLogo**: Custom app logo with theme-aware colors
- **AudiobookTile**: Card display for audiobooks in library
- **CountdownTimerWidget**: Visual display for sleep timer countdown
- **AddBookmarkDialog**: Interface for creating bookmarks
- **TagAssignmentDialog**: Advanced tag management with rename/delete functionality
- **TagsView**: Display and manage tags with visual indicators

## Key Features Implementation

### Advanced Folder Scanning

The new recursive scanning system:
- **Traverses any folder depth** to find audiobooks
- **Identifies audiobook folders** by presence of audio files
- **Handles series and single books** automatically
- **Prevents duplicate chapter detection** by stopping at first audio file level
- **Provides detailed feedback** on scan results
- **Supports progress indication** for large libraries

### Enhanced Metadata Extraction

- **Author detection** from album artist or track artist metadata
- **Priority-based cover art discovery** - embedded metadata takes precedence over folder images
- **Better error handling** for corrupted files
- **Fallback mechanisms** when metadata is unavailable
- **Consistent visual experience** with intelligent cover art selection

### Media Notifications

The app implements media notifications using the just_audio_background plugin, allowing users to control playback from the notification area or lock screen.

### Progress Tracking

The app automatically saves and restores listening progress with in-memory caching for improved performance.

### Sleep Timer

Set timers with real-time countdown display, accessible from any screen during playback.

### Bookmarks

Create named bookmarks at specific points and jump directly to bookmarked positions.

### Responsive UI

Dynamic layout adaptation based on screen orientation with Material Design 3 principles.

### Theme Customization

Customizable accent colors with light/dark mode support and automatic system theme detection.

### Advanced Tag System

Create and manage custom tags to organize your audiobook library:
- **Create custom tags** with intuitive textbox-first interface
- **Rename existing tags** while maintaining all assignments
- **Delete unwanted tags** with confirmation dialogs
- **Bulletproof Favorites** - special system tag that cannot be deleted or renamed
- **Tag assignments** persist across app sessions and data operations

### Enhanced Data Management

Comprehensive backup and restore system with advanced protection:
- **Complete data backup** - tags, favorites, progress, bookmarks, and preferences
- **Corruption detection** - automatic validation of backup file integrity
- **Recovery mechanisms** - fallback options when data issues are detected
- **Version compatibility** - handles migration between app versions
- **Manual export/import** - JSON format with timestamped filenames
- **Automatic backups** - on app start and periodic persistence

### Data Health Monitoring

Built-in system to monitor and maintain data integrity:
- **Tag statistics** - view count and usage of all tags
- **Data validation** - automatic checks for consistency
- **Health dashboard** - accessible through Settings menu
- **Error reporting** - detailed feedback on any data issues
- **Proactive maintenance** - prevents data corruption before it occurs

## Getting Started

### Prerequisites

- Flutter SDK (3.7.2 or higher)
- Android Studio / VS Code with Flutter extensions
- Android/iOS development setup

### Installation

1. Clone the repository
2. Run `flutter pub get` to install dependencies
3. Run `flutter run` to launch the app on a connected device/emulator

## Usage Tips

### For Large Libraries
- Use "Scan for Books" to add your entire audiobook collection at once
- The app will handle any folder organization structure
- Progress is shown for large scanning operations

### For Organized Collections
- Keep series in separate folders for better organization
- Use descriptive folder names as they become the audiobook titles
- Place cover art files in each audiobook folder for best results

### Troubleshooting
- If books aren't found, check file permissions
- Ensure audio files are in supported formats
- Check debug logs for detailed scanning information
- Try scanning smaller folders if issues persist

## Future Roadmap

- Migration to Riverpod for state management
- Cloud synchronization
- Enhanced metadata editing
- Audio effects and equalization
- Audiobook categorization and tagging
- Playlist support
- Statistics dashboard for listening habits
- Text-to-speech support for eBooks
- Improved offline capability
