# Release Notes - v1.6.0 (vs v1.5.0)

## 🌟 What's New

### 📁 Smart Folder Discovery (.nomedia Support)
No more missing books! Widdle Reader can now "see" audiobooks even in folders containing `.nomedia` files.
*   **All Files Access**: We've updated the app to request the "All Files Access" permission on Android 11+. This allows our scanner to find your books even if they are hidden from other gallery and music apps.
*   **Scoped Storage Bypass**: Bypasses system-level restrictions that previously hid audiobook chapters from the library scanner.

### 🔢 Natural Chapter Sorting
Your chapters are now exactly where they belong.
*   **Smart Alphanumeric Sort**: The app now understands that `Chapter 2` comes before `Chapter 10`, even if you haven't used leading zeros in your filenames. 
*   **Deterministic Order**: No more jumping from Chapter 1 straight to Chapter 10—the scanner now groups and sequences all numbers logically.

### 🎨 EQ UI & Intelligence
The Equalizer is now smarter and more helpful:
*   **Active Preset Highlighting**: The preset you've chosen (Podcast, Vocal Boost, etc.) now lights up in the UI so you always know what's active.
*   **Automatic Detection**: When you open the EQ sheet, it automatically detects and highlights the matching preset based on your current slider positions.
*   **Smart Deactivation**: The moment you manually tweak a frequency, the preset highlight disappears, indicating you've moved to a custom profile.

## 🛠️ Fixes & Improvements

### 🔇 Seamless Chapter Skips
*   **Fixed Playback Pauses**: Resolved the issue where audio would "hiccup" or pause when skipping chapters with Audio Effects active. The EQ effect now stays smoothly engaged between chapters.
  
### 🦾 EQ Robustness
*   **Initialization Fix**: Improved how EQ settings are synced with hardware to prevent the "mute on relaunch" bug on certain Android devices.
*   **Generation ID System**: Rapid seeks (dragging the progress slider) are now managed by a "generation" system to ensure only the final state is applied, keeping performance snappy and audio clear.

### 🎄 Holiday Spirit
*   **Themed App Logo**: Updated the application logo with a festive holiday theme!
