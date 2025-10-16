# 🎤 Voice Input with Whisper AI

## Features

Kai's overlay now supports voice input using OpenAI's Whisper AI for speech-to-text transcription!

### How to Use Voice Input

#### Method 1: Circular Menu (Floating Avatar)
1. Tap Kai's avatar to open the circular menu
2. Tap the **microphone button** (bottom-right position)
3. Start speaking (icon changes to mic_off while recording)
4. Tap again to stop recording
5. Your speech is automatically transcribed and sent to Kai

#### Method 2: Chat Window
1. Tap Kai to open chat
2. Tap the **chat button** to expand the full chat window
3. Use the **microphone button** next to the send button
4. Button turns **red** while recording
5. Tap to stop - your speech is transcribed and sent automatically

## Technical Details

### Voice Service
- **Speech-to-Text**: OpenAI Whisper API (`whisper-1` model)
- **Audio Format**: AAC (m4a) - optimal for Whisper
- **Sample Rate**: 44.1kHz
- **Bit Rate**: 128kbps
- **Language**: English (configurable to auto-detect)

### Permissions
- ✅ `RECORD_AUDIO` permission already configured in AndroidManifest
- Permission requested automatically on first use
- No additional setup needed

### API Configuration

The voice service uses your OpenAI API key for Whisper transcription:

```dart
// Voice service uses the same OpenAI API key
static const String openaiApiKey = String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');
```

### Building with Voice Support

#### Debug Build (for testing):
```bash
flutter build apk --debug -t lib/main_overlay.dart --target-platform android-x64 --dart-define=OPENAI_API_KEY=your-key-here
```

#### Release Build (optimized):
```bash
flutter build apk --release -t lib/main_overlay.dart --target-platform android-x64 --dart-define=OPENAI_API_KEY=your-key-here
```

## Code Structure

### New Files
- `lib/services/voice_service.dart` - Whisper API integration and audio recording

### Updated Files
- `lib/main_overlay.dart` - Voice input UI and integration
- `pubspec.yaml` - Added `record` and `permission_handler` packages

### Key Components

#### VoiceService Class
```dart
class VoiceService {
  // Start recording audio
  Future<bool> startRecording()
  
  // Stop recording and get file path
  Future<String?> stopRecording()
  
  // Cancel recording without saving
  Future<void> cancelRecording()
  
  // Transcribe audio with Whisper API
  Future<String?> transcribeAudio(String audioPath)
  
  // All-in-one: record and transcribe
  Future<String?> recordAndTranscribe()
}
```

#### Overlay Integration
- `_startVoiceRecording()` - Begins recording with permission check
- `_stopVoiceRecording()` - Stops, transcribes, and sends message
- `_isRecording` state - Updates UI to show recording status

## UI Indicators

### Recording State
- **Circular Menu**: Microphone icon toggles between `mic` and `mic_off`
- **Chat Window**: Microphone button turns **red** while recording
- **Loading**: Spinner shows while transcribing audio

### Error Handling
- Permission denied → Shows error message
- Recording failed → Shows error message
- Transcription failed → Shows error message
- All errors displayed in the chat error area

## Dependencies

```yaml
dependencies:
  record: ^5.0.0              # Audio recording
  permission_handler: ^11.0.0 # Microphone permission
  audioplayers: ^6.0.0        # Audio playback (already present)
  dio: ^5.5.0                 # HTTP client for Whisper API
```

## Whisper API Costs

OpenAI Whisper API pricing (as of 2025):
- **$0.006 per minute** of audio transcribed
- Average 10-second voice message = **$0.001** (less than 1 cent)
- Very affordable for personal use!

## Tips for Best Results

1. **Speak clearly** - Better enunciation = better transcription
2. **Reduce background noise** - Find a quiet environment
3. **Keep messages short** - Under 30 seconds for faster processing
4. **Wait for transcription** - Processing takes 1-3 seconds typically

## Troubleshooting

### "Failed to start recording"
- Check microphone permission in Android settings
- Ensure no other app is using the microphone

### "Failed to transcribe audio"
- Check internet connection
- Verify OpenAI API key is valid
- Check API quota/credits

### Recording but no transcription
- Check logcat for error details:
  ```bash
  adb logcat | Select-String "Voice|Whisper|Recording"
  ```

## Future Enhancements

Potential improvements:
- [ ] Real-time transcription streaming
- [ ] Language auto-detection
- [ ] Custom wake word detection
- [ ] Background recording permission
- [ ] Voice activity detection (auto-stop on silence)
- [ ] Recording duration indicator
- [ ] Playback recorded audio before sending

## Privacy & Security

- 🔒 Audio files are **temporary** and deleted after transcription
- 🗑️ No audio is stored permanently
- 🌐 Audio sent to OpenAI for transcription (see OpenAI privacy policy)
- 🔐 API key never exposed in code (environment variable only)

## Benchmark

This voice input feature is part of **v0.3-responsive-drag** and later versions.

Enjoy hands-free chatting with Kai! 🎤✨
