# Widdle Reader - Audiobook Player App

Widdle Reader is a feature-rich, modern audiobook player built with Flutter. The app provides a clean, intuitive interface for listening to audiobooks with support for background playback, media notifications, and progress tracking.

**Current Version: 1.0.2** (See [Changelog](./CHANGELOG.md) for details)

## Features

- **Audiobook Library Management**: Browse and manage your audiobook collection
- **Background Playback**: Continue listening when the app is in the background
- **Media Controls**: Control playback from notifications and lockscreen
- **Progress Tracking**: Automatically saves your position in each audiobook
- **Theme Customization**: Light/dark mode with customizable seed colors
- **Responsive Design**: Optimized for both portrait and landscape orientations
- **Chapter Navigation**: Easy navigation between audiobook chapters
- **Sleep Timer**: Set a timer to automatically pause playback after a specified duration
- **Bookmarks**: Add and manage bookmarks at specific points in your audiobooks
- **Variable Playback Speed**: Adjust the playback speed from 0.5x to 2.0x
- **In-Memory Caching**: Enhanced performance with efficient data caching
- **Data Management**: Reset progress and export/import user data
- **Real-time Progress Display**: Visual indicators showing completion percentage

## Tech Stack

- **Flutter**: Cross-platform UI framework
- **Provider**: State management
- **just_audio/just_audio_background**: Audio playback and background services
- **Path Provider/File Picker**: File system interaction
- **Shared Preferences**: Local data storage

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

- **Audiobook**: Represents an audiobook with metadata and chapters
- **Chapter**: Represents a chapter within an audiobook with playback info
- **Bookmark**: Stores user-created bookmarks for specific points in audiobooks

#### Services

- **SimpleAudioService**: Core audio playback functionality
- **AudioHandler**: Manages media session interactions and notifications
- **StorageService**: Handles saving/loading progress and preferences
- **MetadataService**: Extracts metadata from audio files

#### Providers (State Management)

- **AudiobookProvider**: Manages the audiobook library and playback state
- **ThemeProvider**: Handles theme preferences and customization
- **SleepTimerProvider**: Manages the sleep timer functionality

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

## Key Features Implementation

### Media Notifications

The app implements media notifications using the just_audio_background plugin, allowing users to control playback from the notification area or lock screen. The implementation includes:

- Custom notification channel setup
- Metadata display (title, author, cover art)
- Transport controls (play/pause, skip, seek)
- Background playback support

### Progress Tracking

The app automatically saves and restores listening progress:

- Position is saved periodically during playback and when app is paused/closed
- When reopening an audiobook, playback resumes from the last position
- Progress indicators show completion percentage in the library view
- In-memory caching for improved performance

### Sleep Timer

The sleep timer feature allows users to:

- Set a timer for 5, 15, 30, 45, or 60 minutes
- Create custom timer durations
- View real-time countdown display in both player and library screens
- Access the sleep timer from any screen while playback is active

### Bookmarks

The bookmarking system enables users to:

- Create named bookmarks at specific points in an audiobook
- View and manage all bookmarks for an audiobook
- Jump directly to bookmarked positions during playback

### Responsive UI

The app dynamically adjusts its layout based on screen orientation:

- Portrait mode: List view of audiobooks
- Landscape mode: Grid view for better space utilization
- Responsive player screen with optimized controls
- Scrollable interfaces that adapt to different device screen sizes

### Theme Customization

Users can customize the app appearance:

- Light/dark mode with automatic system theme detection
- Customizable accent colors that propagate throughout the UI
- Persistent theme settings between app sessions

### Data Management

Users can manage their app data:

- Reset progress for individual audiobooks
- Export user data for backup
- Import previously exported data
- Manage caching settings

## Getting Started

### Prerequisites

- Flutter SDK (2.0 or higher)
- Android Studio / VS Code with Flutter extensions
- Android/iOS development setup

### Installation

1. Clone the repository
2. Run `flutter pub get` to install dependencies
3. Run `flutter run` to launch the app on a connected device/emulator

## Future Roadmap

- Cloud synchronization
- Enhanced metadata editing
- Audio effects and equalization
- Audiobook categorization and tagging
- Playlist support
- Statistics dashboard for listening habits
- Text-to-speech support for eBooks
