# Native Voice Recording Implementation

## Problem
Flutter plugins like `flutter_sound` don't work in overlay isolates because they require platform channel registration in the main Flutter engine. The overlay runs in a completely separate isolate with its own Flutter engine.

**Error encountered:**
```
MissingPluginException(No implementation found for method openRecorder on channel xyz.canardoux.flutter_sound_recorder)
```

## Solution: Native Android MediaRecorder via MethodChannel

We implemented a **custom native Android audio recorder** that works in overlay isolates by using MethodChannel to communicate with native Kotlin code.

### Components Created

#### 1. AudioRecorderPlugin.kt
**Location:** `android/app/src/main/kotlin/com/homecoming/homecoming_app/AudioRecorderPlugin.kt`

Native Kotlin class that wraps Android's `MediaRecorder` API:
- `startRecording()` - Creates temp file, configures MediaRecorder, starts recording
- `stopRecording()` - Stops recording and returns file path
- `isRecording()` - Returns recording status
- **Format:** AAC (MPEG_4), 44.1kHz, 128kbps - compatible with OpenAI Whisper

#### 2. NativeAudioRecorder.dart
**Location:** `lib/services/native_audio_recorder.dart`

Dart wrapper for the native recorder:
```dart
class NativeAudioRecorder {
  static const MethodChannel _channel = 
    MethodChannel('com.homecoming.app/audio_recorder');
  
  Future<String> startRecording() { ... }
  Future<File?> stopRecording() { ... }
  Future<bool> isRecording() { ... }
}
```

#### 3. Updated VoiceService
**Location:** `lib/services/voice_service.dart`

Simplified voice service using native recorder:
- Removed `flutter_sound` dependency
- Uses `NativeAudioRecorder` instead
- No initialization needed
- Works in overlay isolates

### Integration

#### MainActivity.kt Updated
```kotlin
class MainActivity : FlutterActivity() {
    private var audioRecorderPlugin: AudioRecorderPlugin? = null
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize and register AudioRecorderPlugin
        audioRecorderPlugin = AudioRecorderPlugin(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AudioRecorderPlugin.CHANNEL_NAME
        ).setMethodCallHandler { call, result ->
            audioRecorderPlugin?.handleMethodCall(call, result)
        }
    }
}
```

### How It Works

1. **User taps microphone button** in overlay chat
2. **Dart calls** `_recorder.startRecording()` in `VoiceService`
3. **MethodChannel** sends message to native Android code
4. **AudioRecorderPlugin** creates `MediaRecorder`, starts recording to temp file
5. **Returns** file path to Dart
6. **User releases button** → `stopRecording()` called
7. **File returned** to Dart → sent to Whisper API for transcription

### Advantages Over flutter_sound

✅ **Works in overlay isolates** - MethodChannel available everywhere  
✅ **No plugin registration needed** - Direct native access  
✅ **Simpler code** - No complex initialization  
✅ **Smaller binary** - Removed heavy flutter_sound dependency  
✅ **Better control** - Direct access to Android MediaRecorder  

### Testing

Build and test:
```powershell
flutter clean
flutter pub get
flutter build apk --debug -t lib/main_overlay.dart
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell pm grant com.homecoming.app android.permission.RECORD_AUDIO
adb shell monkey -p com.homecoming.app -c android.intent.category.LAUNCHER 1
```

Monitor logs:
```powershell
adb logcat -s flutter:I AudioRecorderPlugin:D *:E
```

### Expected Log Output

When recording works:
```
🎤 [VoiceService] Starting recording...
🎤 [VoiceService] Microphone permission status: PermissionStatus.granted
🎤 [NativeAudioRecorder] Starting recording...
D AudioRecorderPlugin: Starting recording to: /data/user/0/com.homecoming.app/cache/voice_1234567890.m4a
D AudioRecorderPlugin: Recording started successfully
✅ [NativeAudioRecorder] Recording started: /data/user/0/com.homecoming.app/cache/voice_1234567890.m4a
✅ [VoiceService] Recording started successfully

[User speaks...]

🎤 [NativeAudioRecorder] Stopping recording...
D AudioRecorderPlugin: Recording stopped successfully
✅ [NativeAudioRecorder] Recording stopped: /path/to/file.m4a (45231 bytes)
🎯 Transcribing audio: /path/to/file.m4a
📊 File size: 45231 bytes
```

### Files Changed

- ✅ Created: `android/app/src/main/kotlin/com/homecoming/homecoming_app/AudioRecorderPlugin.kt`
- ✅ Created: `lib/services/native_audio_recorder.dart`
- ✅ Updated: `lib/services/voice_service.dart` (removed flutter_sound, use native)
- ✅ Updated: `android/app/src/main/kotlin/com/homecoming/homecoming_app/MainActivity.kt`
- ✅ Updated: `pubspec.yaml` (removed flutter_sound dependency)

### Next Steps

1. **Test voice recording** - Tap and hold mic button, speak, release
2. **Verify Whisper transcription** - Check if audio is transcribed correctly
3. **Test on real device** - Emulator microphone may behave differently
4. **Optimize** - Add error handling, file cleanup, etc.
5. **Polish UI** - Add recording indicator, waveform animation

### Known Limitations

- Android-only (iOS would need similar native implementation)
- Requires RECORD_AUDIO permission
- Temporary files stored in app cache (auto-cleaned by Android)
- AAC format only (compatible with Whisper API)
