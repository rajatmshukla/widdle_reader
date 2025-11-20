# Release Notes - Widdle Reader v1.0.7

## Release Date
November 20, 2025

## What's New

### 🎨 UI/UX Improvements
- **Fixed Chapter List Gradient Clipping**: Chapter list items with gradient backgrounds now properly clip within their container boundaries during scrolling
- **Improved Car Mode Visibility**: Complete rewrite of Car Mode layout to ensure content is visible in both portrait and landscape orientations
  - Added responsive sizing based on screen orientation
  - Made the layout scrollable to prevent overflow on smaller screens
  - Optimized button sizes and spacing for better usability while driving

### 🚗 Android Auto Enhancements
- Verified and confirmed full Android Auto bridge functionality
- Resume playback from last position now works seamlessly from Android Auto interface
- State synchronization between the app and Android Auto is fully operational

### 📱 Media Notification Updates
- Configured 15-second skip intervals for rewind and fast-forward controls
- Notification click behavior correctly navigates to the playing audiobook screen

## Technical Details

### Bug Fixes
- Resolved gradient overflow issue in chapter lists by adding proper clipping to Material widgets
- Fixed Car Mode layout rendering issues that caused empty screens in certain orientations

### Architecture Improvements
- Enhanced Android Auto Manager state synchronization
- Improved MediaSession metadata updates for better integration with system media controls

## Known Limitations
- The "Stop" button in media notifications cannot be removed with the current version of `just_audio_background` package
- 15-second skip buttons may not appear in all Android versions due to package limitations

## Upgrade Notes
- Version bumped to 1.0.7 (build 9)
- No breaking changes
- Safe to upgrade from version 1.0.6

## For Developers
To build the signed release bundle, ensure you have:
1. Created `android/keystore.properties` from the template
2. Placed your keystore file at the location specified in the properties
3. Run: `flutter build appbundle --release`

---

**Full Changelog**: Compare v1.0.6...v1.0.7 on GitHub
