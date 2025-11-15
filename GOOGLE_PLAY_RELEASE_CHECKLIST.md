# Google Play Release Checklist for Widdle Reader

## ✅ Critical Issues Fixed

### 1. Android Auto/Automotive Conflict ✅ RESOLVED
**Issue**: App declared both `android.hardware.type.automotive` feature and `com.google.android.gms.car.application` metadata.

**Resolution**:
- ✅ Removed `androidx.car.app:app-automotive:1.4.0` dependency
- ✅ Kept only `androidx.car.app:app:1.4.0` for Android Auto support
- ✅ Added explicit exclusion in `AndroidManifest.xml`: 
  ```xml
  <uses-feature android:name="android.hardware.type.automotive" android:required="false" tools:node="remove"/>
  ```

### 2. Security: Hardcoded Credentials ✅ RESOLVED
**Issue**: Keystore credentials were hardcoded in `build.gradle.kts`

**Resolution**:
- ✅ Moved credentials to `android/keystore.properties`
- ✅ Added `keystore.properties` to `.gitignore`
- ✅ Created template file `android/keystore.properties.template`
- ✅ Updated build script to use environment variables as fallback for CI/CD

### 3. Permissions Documentation ✅ RESOLVED
**Issue**: Permissions lacked clear documentation for Google Play review

**Resolution**:
- ✅ Added detailed comments for each permission in `AndroidManifest.xml`
- ✅ All permissions are justified and necessary for app functionality

---

## Pre-Release Build Steps

### Step 1: Clean Build
```bash
cd d:\widdle_reader
flutter clean
flutter pub get
```

### Step 2: Update Version
Update `pubspec.yaml` version number:
```yaml
version: 1.0.7+9  # Update as needed (current: 1.0.6+8)
```

### Step 3: Build Release Bundle (AAB)
```bash
flutter build appbundle --release
```

The AAB will be at: `build\app\outputs\bundle\release\app-release.aab`

### Step 4: Build Release APK (Optional, for testing)
```bash
flutter build apk --release --split-per-abi
```

APKs will be at: `build\app\outputs\flutter-apk\`

---

## Google Play Console Submission Checklist

### App Content
- [ ] Update "What's New" release notes
- [ ] Ensure screenshots are up-to-date (minimum 2, max 8)
- [ ] Add/update feature graphic (1024 x 500 px)
- [ ] Add/update app icon (512 x 512 px)

### Store Listing
- [ ] **Title**: Widdle Reader (or your chosen name)
- [ ] **Short Description**: Compelling 80-character summary
- [ ] **Full Description**: Detailed feature list and benefits
- [ ] **App Category**: Music & Audio
- [ ] **Content Rating**: Complete questionnaire
- [ ] **Privacy Policy**: URL to `privacy-policy.md` (host it on GitHub Pages or your website)

### Privacy & Security
- [ ] **Data Safety Section**: 
  - Declare all data collected (audio files accessed, preferences stored)
  - Specify encryption (if using `flutter_secure_storage`)
  - Explain data sharing practices (none if offline app)
- [ ] **Permissions Justification**: Explain each permission's necessity
  - `READ_MEDIA_AUDIO` / `READ_EXTERNAL_STORAGE`: Access user's audiobook files
  - `FOREGROUND_SERVICE_MEDIA_PLAYBACK`: Background audio playback
  - `POST_NOTIFICATIONS`: Playback controls in notification
  - `WAKE_LOCK`: Keep device awake during playback
  - `INTERNET`: (Only if app needs it - remove if fully offline)

### Testing
- [ ] **Internal Testing**: Upload AAB to Internal Testing track first
- [ ] **Test on Multiple Devices**: Verify on Android 10, 11, 12, 13, 14
- [ ] **Test Android Auto**: Connect to car or use Android Auto Desktop Head Unit
- [ ] **Test Permissions**: Verify all runtime permissions work correctly
- [ ] **Test App Signing**: Ensure Google Play App Signing is enabled

### Pre-Launch Report
- [ ] Wait for Google Play's automated testing results
- [ ] Review crash reports
- [ ] Review security vulnerabilities
- [ ] Review accessibility issues

---

## Android Auto Verification

Since your app supports Android Auto, verify these requirements:

### Media Apps Requirements
- [x] Declares `com.google.android.gms.car.application` metadata
- [x] Implements `MediaBrowserServiceCompat`
- [x] Service exported with `android.media.browse.MediaBrowserService` intent-filter
- [x] Provides browsable media hierarchy
- [x] Updates MediaSession metadata correctly
- [x] Handles playback commands (play, pause, skip, seek)

### Testing Android Auto
```bash
# Install Android Auto DHU (Desktop Head Unit)
# Download from: https://developer.android.com/training/cars/testing

# Connect device and run
adb forward tcp:5277 tcp:5277
./desktop-head-unit.exe

# Check logs
adb logcat | grep -E "WiddleMediaService|AudioSessionBridge|MediaSession"
```

---

## Release Build Verification

### 1. Check APK Size
```bash
# Check AAB size (should be < 150 MB)
ls -lh build\app\outputs\bundle\release\app-release.aab
```

### 2. Verify ProGuard/R8 Obfuscation
```bash
# Decompile APK to verify obfuscation
# Use jadx or similar tool
```

### 3. Test on Physical Device
```bash
# Install release APK
adb install build\app\outputs\flutter-apk\app-arm64-v8a-release.apk

# Test all features:
# - Load audiobooks
# - Playback controls
# - Background playback
# - Notifications
# - Android Auto (if available)
# - Bookmarks
# - Settings
```

---

## Post-Release Monitoring

### Google Play Console
- Monitor crash reports (Vitals section)
- Review user feedback and ratings
- Track installation/uninstallation rates
- Monitor Android Vitals (ANR rate, crash rate)

### Firebase Crashlytics (Optional)
If you add Crashlytics:
```yaml
# Add to pubspec.yaml
dependencies:
  firebase_core: ^latest
  firebase_crashlytics: ^latest
```

---

## Common Google Play Rejection Reasons (and how we've addressed them)

### 1. ❌ Metadata/Feature Conflict
**Issue**: Declaring incompatible features
**Our Fix**: ✅ Removed `app-automotive` dependency, added explicit exclusion

### 2. ❌ Permissions Not Justified
**Issue**: App requests permissions without clear purpose
**Our Fix**: ✅ Added detailed comments in manifest

### 3. ❌ Missing Privacy Policy
**Issue**: Apps handling user data need privacy policy
**Action Needed**: 📝 Host `privacy-policy.md` online and add URL to Play Console

### 4. ❌ Crash on Launch
**Issue**: App crashes during automated testing
**Prevention**: ✅ Test on multiple Android versions before submission

### 5. ❌ Security Vulnerabilities
**Issue**: Using outdated/vulnerable dependencies
**Prevention**: ✅ Keep dependencies updated, run `flutter pub outdated`

---

## Version History

| Version | Build | Status | Date | Notes |
|---------|-------|--------|------|-------|
| 1.0.6   | 8     | Current| -    | Android Auto integration |
| 1.0.7   | 9     | Planned| -    | Google Play release fixes |

---

## Rollback Plan

If critical issues are discovered post-release:

1. **Immediate**: Halt rollout in Google Play Console (limit to 20% initially)
2. **Fix**: Create hotfix branch, address issue
3. **Test**: Thorough testing on affected devices
4. **Release**: Push emergency update with incremented build number
5. **Communicate**: Update store listing with issue acknowledgment

---

## Support & Contact

For issues found after release:
- Monitor Google Play reviews
- Set up support email in Play Console
- Consider adding in-app feedback mechanism

---

## Files Modified for Release

### Critical Changes:
1. `android/app/build.gradle.kts` - Removed automotive dependency, secured credentials
2. `android/app/src/main/AndroidManifest.xml` - Excluded automotive feature, documented permissions
3. `android/keystore.properties` - Created for secure credential storage
4. `.gitignore` - Added keystore files to exclusion list

### New Files:
1. `android/keystore.properties.template` - Template for credentials
2. `GOOGLE_PLAY_RELEASE_CHECKLIST.md` - This document

---

## Final Pre-Submission Command

```bash
# Run this before building the release bundle
flutter analyze
flutter test
flutter build appbundle --release

# Verify the build
echo "Bundle created at: build\app\outputs\bundle\release\app-release.aab"
echo "Bundle size:"
ls -lh build\app\outputs\bundle\release\app-release.aab
```

---

## Contact Google Play Support

If you encounter issues during submission:
- Google Play Console → Help → Contact Support
- Provide: Package name, version code, specific error message
- Be prepared to wait 1-3 business days for response

---

**Last Updated**: November 2, 2025  
**App Version**: 1.0.6+8 → 1.0.7+9 (planned)  
**Status**: ✅ Ready for Google Play submission

