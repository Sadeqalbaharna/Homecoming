# # Homecoming AI Avatar App

A cross-platform Flutter application featuring Kai, an AI avatar with personality and mood dynamics.

## Features

- **Pure Flutter Implementation**: No Python backend required
- **Cross-Platform Support**: Desktop (Windows, macOS, Linux) and Mobile (Android, iOS)
- **AI Integration**: OpenAI GPT-4o/GPT-5 for conversations
- **Text-to-Speech**: ElevenLabs integration for voice responses
- **Dynamic Personality**: Personality traits, mood states, and user affinity tracking
- **Animated Avatar**: Multiple GIF states (idle, attention, thinking, speaking)
- **Real-time Personality Changes**: Visual feedback for personality/mood adjustments

## Requirements

### API Keys (Optional but recommended)
- **OpenAI API Key**: For AI chat functionality
- **ElevenLabs API Key**: For text-to-speech features

### Flutter Environment
- Flutter SDK 3.0.0 or higher
- Dart SDK 3.0.0 or higher

## Installation

### 1. Clone the Repository
```bash
git clone <your-repo-url>
cd homecoming_app
```

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Configure API Keys
Edit `lib/services/ai_service.dart` and add your API keys:
```dart
class AIConfig {
  static const String openAIApiKey = 'your-openai-api-key-here';
  static const String elevenLabsApiKey = 'your-elevenlabs-api-key-here'; // Optional
  static const String googleApiKey = ''; // Optional - not currently used
}
```

## Running the App

### Desktop (Windows/macOS/Linux)
```bash
flutter run -d windows  # For Windows
flutter run -d macos    # For macOS
flutter run -d linux    # For Linux
```

### Mobile (Android/iOS)
```bash
flutter run -d android  # For Android
flutter run -d ios      # For iOS (requires macOS)
```

### Web
```bash
flutter run -d chrome   # For web browsers
```

## Building for Release

### Android APK
```bash
flutter build apk --release
```

### Android App Bundle (for Play Store)
```bash
flutter build appbundle --release
```

### iOS (requires macOS)
```bash
flutter build ios --release
```

### Desktop
```bash
flutter build windows --release  # Windows
flutter build macos --release    # macOS
flutter build linux --release    # Linux
```

## Firebase Integration

This app can be easily integrated with Firebase for:
- Firebase App Distribution (for testing)
- Remote configuration
- Analytics
- Crashlytics

### Adding Firebase
1. Create a Firebase project at https://console.firebase.google.com
2. Add your app platforms (Android/iOS/Web)
3. Download configuration files:
   - `google-services.json` for Android (place in `android/app/`)
   - `GoogleService-Info.plist` for iOS (place in `ios/Runner/`)
4. Add Firebase SDK dependencies to `pubspec.yaml`

## Project Structure

```
lib/
├── main.dart                 # Desktop version (with window_manager)
├── main_mobile.dart         # Mobile-optimized version
├── main_adaptive.dart       # Platform-adaptive entry point
├── services/
│   └── ai_service.dart      # Pure Flutter AI service
└── assets/
    └── avatar/              # GIF animations
        ├── idle.gif
        ├── attention.gif
        ├── thinking.gif
        └── speaking.gif
```

## Platform-Specific Features

### Desktop
- Frameless floating window
- Always-on-top option
- Window dragging
- Transparent background effects

### Mobile
- Full-screen app interface
- Touch-optimized controls
- Responsive layout
- Mobile-friendly chat interface

## API Integration

### OpenAI GPT
- Supports GPT-4o and GPT-5 models
- Context-aware conversations
- Personality-driven responses

### ElevenLabs TTS
- High-quality voice synthesis
- Automatic audio playback
- Base64 audio streaming

## Personality System

Kai features a dynamic personality system with:
- **Big Five Traits**: Extraversion, Intuition, Feeling, Perceiving
- **Mood States**: Valence, Energy, Warmth, Confidence, Playfulness, Focus
- **User Affinity**: Intimacy and Physicality levels
- **Real-time Adjustments**: Visual feedback for personality changes

## Development

### Key Dependencies
- `dio`: HTTP client for API calls
- `audioplayers`: Audio playback
- `shared_preferences`: Local storage
- `gif`: GIF animation support
- `window_manager`: Desktop window management (desktop only)
- `flutter_acrylic`: Transparent effects (desktop only)

### Adding New Features
1. Personality traits can be modified in `ai_service.dart`
2. Avatar states can be added by including new GIF assets
3. API integrations can be extended in the `AIService` class

## Troubleshooting

### Common Issues
1. **API Key Errors**: Ensure API keys are correctly set in `ai_service.dart`
2. **Audio Playback**: Check device audio permissions
3. **Build Errors**: Run `flutter clean && flutter pub get`

### Platform-Specific Issues
- **Windows**: May require Visual Studio Build Tools
- **macOS**: Requires Xcode for iOS builds
- **Android**: Ensure Android SDK is properly configured

## License

[Your License Here]

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request
