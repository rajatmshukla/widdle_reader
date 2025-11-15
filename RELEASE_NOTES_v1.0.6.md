# Release Notes – v1.0.6

## Android Auto Experience
- Expanded the browse tree to include Continue Listening, Recently Played, Favorites, All Audiobooks, and chapter drill-downs.
- Added a native `MediaBrowserServiceCompat` that mirrors Flutter state so Android Auto always sees rich metadata.
- Routed play/pause/seek/skip actions from Android Auto through `AudioSessionBridge` and `SimpleAudioService` for immediate control.
- Promoted the full Now Playing UI (cover art, chapter title, author, progress, speed, transport controls) instead of the loading card.
- Fixed the stuck “Getting your selection” loop by resuming from the last saved chapter/position for every audiobook.
- Ensured the play/pause button on the car head unit stays in sync with real playback state.

## Playback & Metadata Pipeline
- Introduced richer metadata payloads (mediaId, chapter title, author, resume position, cover art) flowing from Flutter to Android.
- Added direct command handlers and `propagateToNative` flags to prevent control-loop feedback.
- Improved saved-position restoration so tapping any book resumes exactly where the listener left off.

## Release Readiness
- Updated the Android manifest to satisfy Play Store policy (removed the automotive hardware feature flag).
- Added R8/ProGuard keep rules to unblock release builds.
- Bumped Flutter dependencies (e.g., `audio_session`) and refreshed widget tests (`AppLogo` smoke test).
- Documented the Android Auto integration workflow and verified `flutter build appbundle --release`.

This release represents every change made after version 1.0.5 and is now ready for internal testing and Play Store submission.

