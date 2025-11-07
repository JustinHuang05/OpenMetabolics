# OpenMetabolics Android Build and Deployment Guide

This directory contains the Android-specific configuration and native code for the OpenMetabolics Flutter application.

## Table of Contents

- [Version Management](#version-management)
- [Building a Release](#building-a-release)
- [Deployment](#deployment)
- [File Structure](#file-structure)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)

## Version Management

### Updating Version Numbers

To create a new version of the app, update the version information in `app/build.gradle`:

```gradle
def flutterVersionCode = '34'        // Increment this (integer)
def flutterVersionName = '1.3.4'     // Update this (e.g., 1.3.4, 1.4.0)
```

**Version Code** (`flutterVersionCode`):

- Must be an integer that increases with each release
- Used internally by Google Play Store to track app versions
- **Must always increase** - cannot decrease or reuse
- Current value: `33`

**Version Name** (`flutterVersionName`):

- User-facing version string (e.g., "1.3.4")
- Follows semantic versioning: `MAJOR.MINOR.PATCH`
- Current value: `1.3.3`

### Versioning Best Practices

1. **Increment version code** for every release (even minor updates)
2. **Update version name** to reflect the release type:

   - **Patch** (1.3.3 → 1.3.4): Bug fixes, small changes
   - **Minor** (1.3.3 → 1.4.0): New features, backward compatible
   - **Major** (1.3.3 → 2.0.0): Breaking changes, major updates

3. **Keep track** of version numbers to avoid conflicts

## Building a Release

### Prerequisites

1. **Signing Key**: Ensure `key.properties` and `upload-keystore.jks` are present
2. **Environment**: Android SDK and build tools installed
3. **Dependencies**: Run `flutter pub get` in project root first

### Build Commands

#### Option 1: App Bundle (Recommended for Google Play)

```bash
cd /path/to/open_metabolics_app
flutter build appbundle --release
```

**Output**: `build/app/outputs/bundle/release/app-release.aab`

**Use Case**: Upload to Google Play Console (recommended format)

#### Option 2: APK (For Direct Distribution)

```bash
cd /path/to/open_metabolics_app
flutter build apk --release
```

**Output**: `build/app/outputs/flutter-apk/app-release.apk`

**Use Case**:

- Direct installation on devices
- Testing before Play Store submission
- Distribution outside Google Play

#### Option 3: Split APKs (Optimized)

```bash
flutter build apk --release --split-per-abi
```

**Output**:

- `app-armeabi-v7a-release.apk`
- `app-arm64-v8a-release.apk`
- `app-x86_64-release.apk`

**Use Case**: Smaller APKs per architecture (optional)

### Build Process

The build process will:

1. **Compile Flutter code** to Dart bytecode
2. **Build Android native code** (Kotlin/Java)
3. **Sign the app** using the keystore in `key.properties`
4. **Optimize and minify** (for release builds)
5. **Generate output** in `build/app/outputs/`

### Verification

After building, verify the version:

```bash
# For APK
aapt dump badging build/app/outputs/flutter-apk/app-release.apk | grep version

# Should show:
# versionCode='34'
# versionName='1.3.4'
```

## Deployment

### Google Play Store Deployment

1. **Update Version**:

   ```gradle
   // In android/app/build.gradle
   def flutterVersionCode = '34'      // Increment
   def flutterVersionName = '1.3.4'   // Update
   ```

2. **Build App Bundle**:

   ```bash
   flutter build appbundle --release
   ```

3. **Upload to Play Console**:
   - Go to [Google Play Console](https://play.google.com/console)
   - Navigate to your app → Production → Create new release
   - Upload `build/app/outputs/bundle/release/app-release.aab`
   - Add release notes
   - Review and publish

### Direct Distribution (APK)

1. **Update Version** (same as above)

2. **Build APK**:

   ```bash
   flutter build apk --release
   ```

3. **Distribute**:
   - Share `build/app/outputs/flutter-apk/app-release.apk`
   - Users must enable "Install from Unknown Sources" on their device

### Testing Before Release

Always test the release build before deploying:

```bash
# Build release APK
flutter build apk --release

# Install on connected device
adb install build/app/outputs/flutter-apk/app-release.apk

# Or use Flutter's install command
flutter install --release
```

## File Structure

```
android/
├── app/
│   ├── build.gradle                    # App-level build config (VERSION HERE)
│   ├── proguard-rules.pro              # ProGuard rules for minification
│   ├── upload-keystore.jks            # Signing keystore (DO NOT COMMIT)
│   ├── key.properties                 # Keystore credentials (DO NOT COMMIT)
│   └── src/
│       └── main/
│           ├── AndroidManifest.xml    # App manifest
│           ├── kotlin/
│           │   └── com/openmetabolics/app/
│           │       ├── MainActivity.kt          # Main activity
│           │       ├── SensorRecordingService.kt  # Sensor service
│           │       └── UploadService.kt        # Upload service
│           └── res/                    # Resources (icons, layouts)
├── build.gradle                        # Project-level build config
├── gradle.properties                   # Gradle properties
├── settings.gradle                      # Gradle settings
└── local.properties                     # Local paths (auto-generated)
```

## Configuration

### Signing Configuration

The app uses a signing key for release builds. Configuration is in `key.properties`:

```properties
storePassword=OpenMetabolics2005#
keyPassword=OpenMetabolics2005#
keyAlias=upload
storeFile=upload-keystore.jks
```

**Security Notes**:

- ⚠️ **Never commit** `key.properties` or `upload-keystore.jks` to version control
- These files are in `.gitignore` for security
- Keep backups of the keystore in a secure location
- **Losing the keystore means you cannot update the app on Play Store**

### Build Configuration

**Key Settings** (`app/build.gradle`):

- **Application ID**: `com.openmetabolics.app`
- **Min SDK**: 24 (Android 7.0)
- **Target SDK**: 35 (Android 15)
- **Compile SDK**: 34
- **Java Version**: 17
- **Kotlin Version**: 1.9.0

### Native Code

**Main Components**:

- **MainActivity.kt**: Main entry point, handles platform channels
- **SensorRecordingService.kt**: Background service for sensor recording
- **UploadService.kt**: Background service for data uploads

## Troubleshooting

### Common Issues

1. **Build Fails: "Keystore file not found"**

   - **Solution**: Ensure `upload-keystore.jks` exists in `android/app/`
   - **Check**: Verify `key.properties` has correct `storeFile` path

2. **Build Fails: "Signing config not found"**

   - **Solution**: Verify `key.properties` exists and has all required fields
   - **Check**: Store password, key password, alias, and file path

3. **Version Code Already Used**

   - **Error**: Play Store rejects upload with "version code already exists"
   - **Solution**: Increment `flutterVersionCode` in `build.gradle`

4. **Build Fails: "Gradle sync failed"**

   - **Solution**:
     ```bash
     cd android
     ./gradlew clean
     cd ..
     flutter clean
     flutter pub get
     ```

5. **APK Too Large**

   - **Solution**: Use `--split-per-abi` to create architecture-specific APKs
   - **Or**: Use App Bundle (AAB) which Google Play optimizes automatically

6. **"INSTALL_FAILED_INVALID_APK"**
   - **Solution**: Ensure you're building release version, not debug
   - **Check**: Use `flutter build apk --release`

### Debugging Builds

**Check Build Output**:

```bash
flutter build apk --release --verbose
```

**View Gradle Logs**:

```bash
cd android
./gradlew build --stacktrace
```

**Clean Build**:

```bash
flutter clean
cd android
./gradlew clean
cd ..
flutter pub get
flutter build apk --release
```

### Version Verification

After building, verify the version was updated correctly:

```bash
# Extract and view version info
aapt dump badging build/app/outputs/flutter-apk/app-release.apk | grep -E "versionCode|versionName"
```

Expected output:

```
versionCode='34' versionName='1.3.4'
```

## Quick Reference

### Complete Deployment Workflow

```bash
# 1. Update version in android/app/build.gradle
#    def flutterVersionCode = '34'
#    def flutterVersionName = '1.3.4'

# 2. Clean previous builds (optional but recommended)
flutter clean

# 3. Get dependencies
flutter pub get

# 4. Build release
flutter build appbundle --release

# 5. Verify version
aapt dump badging build/app/outputs/bundle/release/app-release.aab | grep version

# 6. Upload to Play Console
# Go to: https://play.google.com/console
# Upload: build/app/outputs/bundle/release/app-release.aab
```

### Version Number Reference

| Version Name | Version Code | Description        |
| ------------ | ------------ | ------------------ |
| 1.3.3        | 33           | Current version    |
| 1.3.4        | 34           | Next patch release |
| 1.4.0        | 35           | Next minor release |
| 2.0.0        | 36           | Next major release |

**Remember**: Version code must always increase, even if version name stays the same.

---

**Last Updated**: See git history for latest changes.

**Questions or Issues?**: Check the troubleshooting section or review Flutter/Android build documentation.
