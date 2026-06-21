# Homecoming AI Avatar App

🤖 **A cross-platform Flutter application featuring Kai, an AI avatar with dynamic personality and mood states.**

## ✨ Features

- **Pure Flutter Implementation** - No Python backend required
- **Cross-Platform Support** - Desktop (Windows, macOS, Linux) and Mobile (Android, iOS)  
- **AI Integration** - OpenAI GPT-4o/GPT-5 for intelligent conversations
- **Text-to-Speech** - ElevenLabs integration for voice responses
- **Dynamic Personality System** - Real-time personality traits, mood states, and user affinity tracking
- **Animated Avatar** - Multiple GIF states (idle, attention, thinking, speaking)
- **Visual Feedback** - Real-time personality/mood change indicators

## 🚀 Quick Start

```bash
# Clone the repository
git clone https://github.com/yourusername/homecoming-ai-avatar.git
cd homecoming-ai-avatar

# Install dependencies
flutter pub get

# Run on desktop
flutter run -d windows

# Run on mobile (Android)
flutter run -d android
```

## 📱 Ready-to-Install APK

A pre-built Android APK is available in the releases section or build locally:
```bash
flutter build apk --release
```
APK will be located at: `build/app/outputs/flutter-apk/app-release.apk`

## 🔧 Configuration

Add your API keys in `lib/services/ai_service.dart`:
```dart
class AIConfig {
  static const String openAIApiKey = 'your-openai-api-key-here';
  static const String elevenLabsApiKey = 'your-elevenlabs-api-key-here'; // Optional
}
```

## 📚 Documentation

- **[Setup Guide](README.md)** - Complete installation and running instructions
- **[Firebase Integration](FIREBASE_SETUP.md)** - Deploy via Firebase App Distribution  
- **[Deployment Summary](DEPLOYMENT_SUMMARY.md)** - Build and distribution guide

## 🎯 Personality System

Kai features a sophisticated personality system with:
- **Big Five Traits**: Extraversion, Intuition, Feeling, Perceiving
- **Mood Dynamics**: Valence, Energy, Warmth, Confidence, Playfulness, Focus  
- **User Affinity**: Intimacy and Physicality levels
- **Real-time Adjustments**: Visual feedback for all personality changes

## 🏗️ Architecture

- **Desktop**: Frameless floating window with transparency effects
- **Mobile**: Touch-optimized full-screen interface
- **AI Service**: Direct API integration with OpenAI and ElevenLabs
- **Local Storage**: SharedPreferences for personality persistence
- **Cross-Platform**: Adaptive UI that detects and optimizes for each platform

## 📦 Releases

**Latest Release**: v1.0.0
- Android APK: Ready for installation
- Cross-platform support
- Pure Flutter implementation

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- OpenAI for GPT API
- ElevenLabs for Text-to-Speech
- Flutter team for the amazing framework