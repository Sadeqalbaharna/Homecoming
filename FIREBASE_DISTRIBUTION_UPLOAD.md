# Firebase Distribution Upload Instructions

## ⚠️ Firebase CLI Permission Issue

The Firebase CLI is encountering a 403 permission error when trying to upload to App Distribution. This typically means:

1. App Distribution API is not enabled in Firebase Console
2. Your Google account doesn't have the necessary permissions
3. Service account credentials need to be configured

## 📦 Release Files Ready

**APK Location:**
- `releases/homecoming-v0.6.0-voice-input.apk` (47.6 MB)
- `build/app/outputs/flutter-apk/app-release.apk` (original)

**Release Notes:**
- `releases/v0.6.0_RELEASE_NOTES.md`

**Version:** 0.6.0+6

## 🔧 Manual Upload Methods

### Method 1: Firebase Console (Recommended)

1. **Open Firebase Console:**
   - Go to https://console.firebase.google.com/
   - Select project: `homecoming-88ff3`

2. **Navigate to App Distribution:**
   - Click "App Distribution" in left sidebar (under "Release & Monitor")
   - If not visible, enable it: Settings → Integrations → App Distribution

3. **Upload Release:**
   - Click "Get started" or "Distribute app"
   - Select Android app: `com.homecoming.app`
   - Click "Upload" or drag `releases/homecoming-v0.6.0-voice-input.apk`
   - Add release notes from `v0.6.0_RELEASE_NOTES.md`
   - Select testers group
   - Click "Distribute"

### Method 2: Fix Firebase CLI Permissions

**Enable App Distribution API:**
```powershell
# Open Google Cloud Console
Start-Process "https://console.cloud.google.com/apis/library/firebaseappdistribution.googleapis.com?project=homecoming-88ff3"

# Enable the API
# Then try again:
firebase appdistribution:distribute releases\homecoming-v0.6.0-voice-input.apk `
  --app 1:1037590530494:android:48c2e9c93f45ced31ee38b `
  --release-notes-file releases\v0.6.0_RELEASE_NOTES.md `
  --groups testers
```

**Grant Permissions:**
1. Go to Firebase Console → Project Settings → Users and Permissions
2. Make sure your account (sadeq.albaharna@gmail.com) has "Firebase App Distribution Admin" role
3. Save and try uploading again

### Method 3: Direct Device Installation

**For immediate testing on your real device:**

1. **Connect device via USB:**
```powershell
adb devices
adb install releases\homecoming-v0.6.0-voice-input.apk
adb shell pm grant com.homecoming.app android.permission.RECORD_AUDIO
```

2. **Or use wireless installation:**
   - Copy `releases/homecoming-v0.6.0-voice-input.apk` to your device
   - Enable "Install from unknown sources" in Settings
   - Open the APK file on device
   - Install and grant permissions

## 📝 Release Notes Summary

**v0.6.0 - Native Voice Input**

Key Features:
- ✅ Voice recording with native Android MediaRecorder
- ✅ WhisperAI transcription integration
- ✅ Secure API key storage (Android Keystore)
- ✅ Dev mode for testing
- ✅ Works in overlay isolate

Testing Status:
- ✅ Recording: Fully functional (42 KB file from 3s recording)
- ⏳ Transcription: Ready (needs internet on real device)

## 🎯 Git Tag & Commit

```powershell
git add .
git commit -m "v0.6.0: Native voice input with WhisperAI

- Implemented native Android MediaRecorder for overlay isolate
- Added WhisperAI transcription integration
- Added secure API key storage with Android Keystore
- Added dev mode for convenient testing
- Removed flutter_sound dependency
- Fixed voice recording in overlay isolate
- APK: 47.6 MB, fully functional recording
- Ready for real device testing"

git tag -a v0.6.0-voice-input -m "Native voice recording with Whisper AI"
git push origin main --tags
```

## 🚀 Testing on Real Device

**Expected Flow:**
1. Install APK on phone
2. Open app → Enter API keys (or skip if dev mode)
3. Tap chat → Tap and hold mic 🎤
4. Speak message
5. Release → See transcription
6. AI responds

**Check logs:**
```powershell
adb logcat -s flutter:I AudioRecorderPlugin:D *:E
```

## 📊 Build Information

- **Build Type:** Release
- **Version:** 0.6.0+6
- **APK Size:** 47.6 MB
- **Min SDK:** 24 (Android 7.0)
- **Target SDK:** 35 (Android 15)
- **Compile SDK:** 35

---

**Next Steps:**
1. Upload to Firebase Console manually (Method 1)
2. Or fix CLI permissions and retry
3. Test on real device
4. Commit and tag the release
