# Widdle Reader - Modern Audiobook Player

<div align="center">

**A beautiful, feature-rich audiobook player built with Flutter**

[![Version](https://img.shields.io/badge/version-1.4.0-blue.svg)](https://github.com/rajatmshukla/widdle_reader)
[![Flutter](https://img.shields.io/badge/Flutter-3.7.2+-02569B.svg?logo=flutter)](https://flutter.dev)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

[Features](#features) • [Installation](#installation) • [Usage](#usage) • [Architecture](#architecture) • [Contributing](#contributing)

</div>

---

## 🎯 Overview

Widdle Reader is a modern, intuitive audiobook player designed for audiobook enthusiasts. Built with Flutter, it offers a seamless listening experience with powerful features including Android Auto integration, customizable themes, intelligent library management, and robust playback controls.

**Current Version: 1.3.0** | [Release Notes](./RELEASE_NOTES_v1.3.0.md) | [Changelog](./CHANGELOG.md)

## ✨ Features

### 🎵 Playback & Audio
- **Advanced Audio Engine**: Powered by `just_audio` with background playback support
- **Variable Speed Control**: Adjust playback speed from 0.5x to 3.0x
- **15-Second Skip Controls**: Quick navigation with rewind and fast-forward
- **Chapter Navigation**: Seamless chapter-to-chapter playback with auto-progression
- **Sleep Timer**: Set timers with real-time countdown display
- **Position Memory**: Automatically resumes from last played position

### 📚 Library Management
- **Intelligent Folder Scanning**: Recursive scanning supports any folder organization
- **Multiple Audio Formats**: MP3, M4A, M4B, WAV, OGG, AAC, FLAC, OPUS
- **Embedded Chapter Support**: Automatic extraction of chapters from M4B files using FFmpeg
- **Smart Cover Art**: Priority-based extraction (embedded metadata → folder images)
- **Metadata Extraction**: Automatic detection of title, author, and album information
- **Tag System**: Create custom tags and organize your library (with bulletproof Favorites)
- **Book Reviews**: Write rich-text reviews, rate books, and track your thoughts with a built-in editor
- **Reviews Hub**: Centralized view of all your reviewed books with search across review content
- **Bookmarks**: Create named bookmarks at any point in your audiobooks

### 🚗 Android Auto Integration
- **Full Android Auto Support**: Native integration with car interfaces
- **Resume Playback**: Continue from last position directly from Android Auto
- **Browse Library**: Access "Continue Listening", "Recent", "Favorites", and "All Books"
- **Voice Search**: Find audiobooks with voice commands
- **Rich Metadata Display**: Shows cover art, progress, and chapter information

### 🎨 User Interface
- **Material Design 3**: Modern, clean interface following latest design principles
- **Theme Customization**: Light/dark mode with customizable seed colors (43 color options)
- **Responsive Layouts**: Optimized for portrait, landscape, and tablets
- **Car/Bike Mode**: Simplified fullscreen controls for distraction-free listening
- **Smooth Animations**: Polished transitions and staggered entry animations
- **Gradient Progress Indicators**: Visual feedback for playback and library progress

### 🔧 Advanced Features
- **Data Backup & Restore**: Export/import all app data including progress and bookmarks
- **Corruption Detection**: Automatic validation and recovery mechanisms
- **Progress Tracking**: Visual completion indicators and detailed time displays
- **Media Notifications**: Full lockscreen and notification controls
- **Audio Session Management**: Handles interruptions (calls, other media) intelligently
- **In-Memory Caching**: Improved performance for large libraries


## 🚀 Installation

### For Users

**Coming Soon**: Download from Google Play Store

### For Developers

#### Prerequisites
- Flutter SDK 3.7.2 or higher
- Dart SDK 3.7.2 or higher
- Android Studio / VS Code with Flutter extensions
- Android SDK (API 29+) for Android development

#### Clone and Run

```bash
# Clone the repository
git clone https://github.com/rajatmshukla/widdle_reader.git
cd widdle_reader

# Install dependencies
flutter pub get

# Run on connected device
flutter run

# Build release APK
flutter build apk --release

# Build App Bundle for Play Store
flutter build appbundle --release
```

#### Signing Configuration (Required for Release Builds)

1. Create keystore properties file:
   ```bash
   cp android/keystore.properties.template android/keystore.properties
   ```

2. Generate or use existing keystore:
   ```bash
   keytool -genkey -v -keystore widdle_reader.keystore \
     -alias widdle_reader -keyalg RSA -keysize 2048 -validity 10000
   ```

3. Update `android/keystore.properties` with your credentials

## 📖 Usage

### Adding Audiobooks

#### Method 1: Batch Scan (Recommended for Large Libraries)
1. Tap the **"+"** button in the library
2. Select **"Scan for Books"**
3. Choose your root audiobooks folder
4. The app recursively scans all subfolders and imports audiobooks

#### Method 2: Single Book
1. Tap the **"+"** button
2. Select **"Add Single Book"**
3. Choose the specific audiobook folder

### Supported Folder Structures

Widdle Reader works with **any folder organization**:

**Single Books:**
```
Audiobooks/
└── The Great Gatsby/
    ├── chapter1.m4a
    ├── chapter2.m4a
    └── cover.jpg
```

**Series:**
```
Audiobooks/
└── Harry Potter/
    ├── Book 1 - Philosopher's Stone/
    │   ├── 01.mp3
    │   └── 02.mp3
    └── Book 2 - Chamber of Secrets/
        ├── 01.mp3
        └── cover.jpg
```

**Mixed Structure:**
```
Audiobooks/
├── Fiction/
│   ├── 1984/
│   │   └── full.m4b
│   └── Dune/
│       ├── part1.m4a
│       └── part2.m4a
└── Non-Fiction/
    └── Sapiens/
        ├── ch1.mp3
        └── cover.png
```

### Cover Art Priority
1. **Embedded metadata** in audio files (highest priority)
2. **Image files** in audiobook folder:
   - `cover.jpg/png/webp`
   - `folder.jpg/png/webp`
   - `albumart.jpg/png/webp`
   - `front.jpg/png/webp`
   - `artwork.jpg/png/webp`

### Android Auto Usage
1. Connect your phone to Android Auto
2. Open Widdle Reader audio section
3. Browse or resume your audiobooks
4. Control playback with steering wheel or touchscreen controls

## 🏗️ Architecture

### Tech Stack
- **Framework**: Flutter 3.7.2+
- **State Management**: Provider + Riverpod (hybrid)
- **Audio Playback**: 
  - `just_audio` (v0.9.46)
  - `just_audio_background` (v0.0.1-beta.10)
  - `audio_session` (v0.1.25)
- **Metadata**: 
  - `flutter_media_metadata` (v1.0.0)
  - `ffmpeg_kit_flutter_new_audio` (v2.0.0)
- **Storage**: `shared_preferences`, `sqflite`
- **File System**: `path_provider`, `file_picker`
- **UI**: Material Design 3, `flutter_colorpicker`

### Project Structure

```
lib/
├── main.dart                    # App entry point
├── theme.dart                   # Material Design 3 theme
├── models/                      # Data models
│   ├── audiobook.dart          # Audiobook model
│   ├── chapter.dart            # Chapter model with embedded support
│   ├── bookmark.dart           # Bookmark model
│   └── tag.dart                # Tag model
├── providers/                   # State management
│   ├── audiobook_provider.dart # Library & playback state
│   ├── theme_provider.dart     # Theme preferences
│   ├── sleep_timer_provider.dart
│   └── tag_provider.dart       # Tag management
├── screens/                     # UI screens
│   ├── splash_screen.dart
│   ├── library_screen.dart     # Main library view
│   ├── simple_player_screen.dart # Playback interface
│   ├── settings_screen.dart
│   └── bookmarks_screen.dart
├── services/                    # Business logic
│   ├── simple_audio_service.dart # Core audio playback
│   ├── storage_service.dart    # Data persistence
│   ├── metadata_service.dart   # Metadata extraction
│   ├── android_auto_manager.dart # Android Auto bridge
│   └── ffmpeg_helper.dart      # Chapter extraction
├── widgets/                     # Reusable components
│   ├── app_logo.dart
│   ├── audiobook_tile.dart
│   ├── add_bookmark_dialog.dart
│   └── tag_assignment_dialog.dart
└── utils/                       # Utility functions
    ├── helpers.dart
    └── responsive_utils.dart

android/app/src/main/kotlin/com/widdlereader/app/
├── MainActivity.kt              # Android entry point
├── auto/
│   ├── WiddleReaderMediaService.kt  # Android Auto service
│   └── AudioSessionBridge.kt    # Flutter ↔ Native bridge
```

### Key Design Patterns

#### Clean Architecture
- Separation of concerns (Models, Services, UI)
- Dependency injection via Provider
- Single responsibility principle

#### State Management
- **Provider**: Global app state (theme, audiobooks)
- **Riverpod**: Feature-specific state (tags, sleep timer)
- **StreamBuilder**: Reactive playback state updates

#### Android Auto Bridge
- **Dual-layer architecture**:
  1. Flutter layer: `AndroidAutoManager` (Dart)
  2. Native layer: `AudioSessionBridge` (Kotlin)
- **Synchronization**: SharedPreferences + MethodChannel
- **Resume Logic**: Automatic position restoration from storage

## 🔄 Recent Updates (v1.4.0)

**A Major Aesthetic & Feature Update!**

*   **🏆 15+ New Achievements**: From "Session Legend" to "Speed Demon", we've greatly expanded the ways you can track your progress.
*   **✍️ Beautiful Review Editor**: A completely redesigned, glassmorphic review experience with dynamic themes that match your book cover.
*   **✨ Smart Sync**: Widdle Reader now automatically keeps your library in sync with your files.

[👉 Check out the full Release Notes for details!](RELEASE_NOTES_v1.4.0.md)

## 🛣️ Roadmap

### Planned Features
- [ ] Cloud synchronization across devices
- [ ] Playlist support
- [ ] Audio equalizer
- [ ] Statistics dashboard (listening time, progress graphs)
- [ ] Enhanced metadata editing
- [ ] Smart recommendations
- [ ] Integration with audiobook services (Audible, Librivox)
- [ ] Offline-first architecture improvements

### Under Consideration
- [ ] Text-to-speech for eBooks (ePub support)
- [ ] Multi-language support
- [ ] Chromecast integration
- [ ] Widget for home screen

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Development Guidelines
- Follow Flutter/Dart style guide
- Write tests for new features
- Update documentation as needed
- Ensure backward compatibility

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **just_audio** team for the excellent audio playback library
- **Flutter** team for the amazing framework
- **Material Design** team for design guidelines
- All open-source contributors whose libraries made this possible

## 📧 Contact

**Developer**: Rajat Shukla  
**Repository**: [github.com/rajatmshukla/widdle_reader](https://github.com/rajatmshukla/widdle_reader)  
**Issues**: [Report bugs or request features](https://github.com/rajatmshukla/widdle_reader/issues)

---

<div align="center">

**Made with ❤️ using Flutter**

⭐ Star this repo if you find it useful!

</div>
