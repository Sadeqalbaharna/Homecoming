# Firebase Setup Guide for Homecoming App

Follow these steps to integrate Firebase with your Homecoming AI Avatar app.

## 1. Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Click "Create a project"
3. Enter project name: `homecoming-ai-avatar`
4. Enable Google Analytics (optional)
5. Select Analytics account or create new one
6. Click "Create project"

## 2. Add Android App

1. In Firebase Console, click "Add app" → Android
2. Enter Android package name: `com.homecoming.homecoming_app`
3. Enter app nickname: `Homecoming AI Avatar`
4. Download `google-services.json`
5. Place file in `android/app/google-services.json`

## 3. Add iOS App (if building for iOS)

1. Click "Add app" → iOS
2. Enter iOS bundle ID: `com.homecoming.homecomingApp`
3. Enter app nickname: `Homecoming AI Avatar`
4. Download `GoogleService-Info.plist`
5. Place file in `ios/Runner/GoogleService-Info.plist`

## 4. Configure Android Build

Add to `android/build.gradle` (project level):
```gradle
buildscript {
    dependencies {
        // Add this line
        classpath 'com.google.gms:google-services:4.4.0'
    }
}
```

Add to `android/app/build.gradle` (app level):
```gradle
// Add at the top
apply plugin: 'com.google.gms.google-services'

dependencies {
    // Add Firebase SDKs
    implementation platform('com.google.firebase:firebase-bom:33.1.2')
    implementation 'com.google.firebase:firebase-analytics'
}
```

## 5. Add Flutter Firebase Dependencies

Add to `pubspec.yaml`:
```yaml
dependencies:
  firebase_core: ^3.3.0
  firebase_analytics: ^11.2.1
  firebase_app_distribution: ^0.5.0  # For testing distribution
```

## 6. Initialize Firebase in Flutter

Update `lib/main.dart`:
```dart
import 'package:firebase_core/firebase_core.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // ... rest of your main function
}
```

## 7. Firebase App Distribution (for testing)

1. Install Firebase CLI: `npm install -g firebase-tools`
2. Login: `firebase login`
3. Initialize in project: `firebase init`
4. Select "App Distribution"
5. Build release APK: `flutter build apk --release`
6. Upload to distribution:
   ```bash
   firebase appdistribution:distribute build/app/outputs/flutter-apk/app-release.apk \
     --app your-firebase-app-id \
     --testers "email1@example.com,email2@example.com"
   ```

## 8. Alternative: Manual APK Distribution

1. Build release APK: `flutter build apk --release`
2. APK location: `build/app/outputs/flutter-apk/app-release.apk`
3. Transfer to phone via:
   - USB cable
   - Email attachment
   - Cloud storage (Google Drive, Dropbox)
   - ADB install: `adb install app-release.apk`

## 9. Enable Unknown Sources (Android)

To install APK manually:
1. Go to Settings → Security
2. Enable "Unknown sources" or "Install unknown apps"
3. Allow installation from your chosen source

## 10. Testing on Device

1. Enable Developer Options:
   - Go to Settings → About Phone
   - Tap Build Number 7 times
2. Enable USB Debugging:
   - Settings → Developer Options → USB Debugging
3. Connect phone via USB
4. Run: `flutter run -d android`

## Troubleshooting

### Common Issues
- **Build errors**: Run `flutter clean && flutter pub get`
- **Firebase not found**: Ensure `google-services.json` is in correct location
- **Permission errors**: Check Android manifest permissions

### Required Permissions (android/app/src/main/AndroidManifest.xml)
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
```

## Release Checklist

- [ ] Firebase project created
- [ ] Android app added to Firebase
- [ ] `google-services.json` downloaded and placed
- [ ] Firebase dependencies added
- [ ] Release APK builds successfully
- [ ] App installs and runs on test device
- [ ] API keys configured for production use
- [ ] App Distribution configured (optional)