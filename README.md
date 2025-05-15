# Widdle Reader - Audiobook Player App

Widdle Reader is a feature-rich, modern audiobook player built with Flutter. The app provides a clean, intuitive interface for listening to audiobooks with support for background playback, media notifications, and progress tracking.

## Features

- **Audiobook Library Management**: Browse and manage your audiobook collection
- **Background Playback**: Continue listening when the app is in the background
- **Media Controls**: Control playback from notifications and lockscreen
- **Progress Tracking**: Automatically saves your position in each audiobook
- **Theme Customization**: Light/dark mode with customizable seed colors
- **Responsive Design**: Optimized for both portrait and landscape orientations
- **Chapter Navigation**: Easy navigation between audiobook chapters

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

#### Services

- **SimpleAudioService**: Core audio playback functionality
- **AudioHandler**: Manages media session interactions and notifications
- **StorageService**: Handles saving/loading progress and preferences
- **MetadataService**: Extracts metadata from audio files

#### Providers (State Management)

- **AudiobookProvider**: Manages the audiobook library and playback state
- **ThemeProvider**: Handles theme preferences and customization

#### Screens

- **SplashScreen**: Initial loading screen
- **LibraryScreen**: Main audiobook collection view
- **SimplePlayerScreen**: Audiobook playback interface
- **SettingsScreen**: App configuration options

#### Widgets

- **AppLogo**: Custom app logo with theme-aware colors
- **AudiobookTile**: Card display for audiobooks in library
- **SeekBar**: Custom audio progress indicator

## Key Features Implementation

### Media Notifications

The app implements media notifications using the just_audio_background plugin, allowing users to control playback from the notification area or lock screen. The implementation includes:

- Custom notification channel setup
- Metadata display (title, author, cover art)
- Transport controls (play/pause, skip, seek)
- Background playback support

### Progress Tracking

The app automatically saves and restores listening progress:

- Position is saved periodically during playback
- When reopening an audiobook, playback resumes from the last position
- Progress indicators show completion percentage in the library view

### Responsive UI

The app dynamically adjusts its layout based on screen orientation:

- Portrait mode: List view of audiobooks
- Landscape mode: Grid view for better space utilization
- Responsive player screen with optimized controls

### Theme Customization

Users can customize the app appearance:

- Light/dark mode with automatic system theme detection
- Customizable accent colors that propagate throughout the UI
- Persistent theme settings between app sessions

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

- Playlist support
- Sleep timer functionality
- Cloud synchronization
- Enhanced metadata editing
- Audio effects and equalization
- Audiobook categorization and tagging
