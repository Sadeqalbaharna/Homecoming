# Copilot Instructions - Homecoming AI Avatar App

This workspace contains **Homecoming**, a cross-platform Flutter application featuring Kai, an AI avatar with personality dynamics, Firebase persistence, and voice integration.

## 🎯 Quick Start for Copilot

### Project Type
- **Flutter**: Cross-platform mobile (Android/iOS) + desktop (Windows/macOS/Linux)
- **State Management**: Riverpod (`hooks_riverpod 2.5.1`)
- **Backend**: Firebase Realtime Database + Cloud Functions
- **AI Integration**: OpenAI GPT-4o/GPT-5, Google Search, ElevenLabs TTS

### Key Architecture Patterns

#### Service Layer (lib/services/)
All business logic lives in service classes. Common services:
- `ai_service.dart` - OpenAI integration
- `firebase_service.dart` - Cloud data sync
- `voice_activation_service.dart` - Wake word detection
- `dynamic_ambient_service.dart` - Mood and context system
- `knowledge_graph_service.dart` - Semantic memory

**Pattern**: Services are singletons injected via Riverpod providers in `voice_provider.dart`

#### Providers (lib/voice_provider.dart)
All services exposed as Riverpod providers:
```dart
final aiServiceProvider = Provider((ref) => AIService());
final firebaseProvider = Provider((ref) => FirebaseService());
```

#### UI Layer (lib/screens/ and lib/widgets/)
- **Screens**: Page-level widgets (one per screen)
- **Widgets**: Reusable UI components
- **Pattern**: Thin UI that consumes providers via `ref.watch()`, logic in services

#### Models (lib/models/)
- `knowledge_node.dart` - Semantic memory unit
- Other data classes following Dart/JSON serialization patterns

### Entry Points (Choose Based on Target)
- `lib/main.dart` - Default (desktop/adaptive)
- `lib/main_mobile.dart` - Mobile-specific (Android/iOS)
- `lib/main_overlay.dart` - Overlay/transparent window mode
- `lib/main_test.dart` - Testing
- `lib/main_adaptive.dart` - Adaptive layout

Run with: `flutter run -t lib/main_overlay.dart`

### Firebase Setup
- **Project**: homecoming-74f73
- **Database**: Realtime RTDB (europe-west1)
- **Config**: [lib/firebase_options.dart](lib/firebase_options.dart)
- **Features**: Cross-device personality sync, memory persistence

### API Key Management

#### Development (Recommended)
1. Set environment variables:
   ```bash
   $env:OPENAI_API_KEY = "sk-..."
   $env:ELEVENLABS_API_KEY = "..."
   flutter run --dart-define=OPENAI_API_KEY=$env:OPENAI_API_KEY
   ```

2. OR use `lib/dev_config.dart` for frequent rebuilds:
   ```dart
   const bool USE_DEV_MODE = true;
   static const String DEV_OPENAI_KEY = 'sk-...';
   static const String DEV_ELEVENLABS_KEY = '...';
   ```
   - Auto-restores keys on each install
   - CRITICAL: Set `USE_DEV_MODE = false` before distribution

#### Production
- Keys stored securely via `flutter_secure_storage`
- Never commit to git
- See [API_SECURITY.md](API_SECURITY.md)

## 🚀 Common Commands

```bash
# Setup
flutter pub get                          # Install/update dependencies

# Development
flutter run                              # Run on connected device (uses default entry point)
flutter run -t lib/main_overlay.dart    # Run overlay version
flutter run --debug                     # Debug build with breakpoints

# Testing
flutter test                             # Run unit/widget tests
flutter analyze                          # Lint analysis

# Building
flutter build apk --debug               # Android debug APK
flutter build apk --release             # Android release APK
flutter build windows               # Windows executable
flutter build linux                 # Linux executable

# Debugging
flutter doctor                          # Check environment setup
flutter devices                         # List connected devices
flutter logs                            # View app logs
```

## 📋 Common Development Tasks

### Adding a New Service
1. Create `lib/services/your_service.dart`
2. Implement service class with public methods
3. Export as Riverpod provider in `lib/voice_provider.dart`: `final yourServiceProvider = Provider(...)`
4. Consume in UI via `ref.watch(yourServiceProvider)`

Example pattern:
```dart
// services/your_service.dart
class YourService {
  Future<T> someMethod() async { /* ... */ }
}

// voice_provider.dart
final yourServiceProvider = Provider((ref) => YourService());

// screens/some_screen.dart
class SomeScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(yourServiceProvider);
    // use service...
  }
}
```

### Adding Firebase Persistence
1. Use `firebase_service.dart` to sync to Realtime Database
2. Cloud Functions can process triggers server-side
3. Data persists across devices when user logs in

### Adding Voice Commands
1. Update `voice_activation_service.dart` for new wake words
2. Route to `unified_voice_music.py` for command processing (Python backend)
3. Result triggers Firebase listener updates

### Testing
- **Widget Tests**: `test/` directory
- **Unit Tests**: Mock services using Riverpod's test providers
- Run with: `flutter test --verbose`

## ⚠️ Common Pitfalls

| Issue | Solution |
|-------|----------|
| **API keys missing** | Check `USE_DEV_MODE` setting or environment variables before running |
| **Firebase not connected** | Verify `google-services.json` and Firebase project credentials |
| **App won't build** | Run `flutter pub get` then `flutter clean` && `flutter pub get` |
| **No database sync** | Ensure `firebase_database` is initialized before reading data |
| **Overlay not appearing** | Use `lib/main_overlay.dart` entry point, not `main.dart` |
| **Multiple entry points** | If app seems stuck, check which entry point you're running |
| **Personality not persisting** | Verify Firebase Realtime DB permissions and structure |

## 📚 Essential Documentation

- [README.md](README.md) - Project overview, tester & developer guides
- [START_HERE.md](START_HERE.md) - Unified module quick reference
- [DEV_MODE_GUIDE.md](DEV_MODE_GUIDE.md) - API key setup for development
- [FIREBASE_SETUP.md](FIREBASE_SETUP.md) - Firebase & CI/CD configuration
- [API_SECURITY.md](API_SECURITY.md) - Security best practices
- [MODULAR_ARCHITECTURE.md](MODULAR_ARCHITECTURE.md) - Backend fixtures
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - Command reference

## 🔑 Key Technologies

| Component | Package | Version |
|-----------|---------|---------|
| State Mgmt | `hooks_riverpod` | 2.5.1 |
| Firebase | `firebase_core`, `firebase_database`, `cloud_functions` | 3.6.0+, 11.1.4+, 5.1.3+ |
| Audio | `audioplayers` | 6.0.0+ |
| UI/Animation | `lottie`, `gif` | 3.1.0, 2.3.0 |
| Desktop | `window_manager`, `flutter_acrylic` | 0.3.9, 1.1.4 |
| Security | `flutter_secure_storage` | 9.0.0 |
| Storage | `shared_preferences`, `path_provider` | 2.2.2, 2.1.1 |

## 🏗️ Project Structure

```
lib/
├── main.dart, main_mobile.dart, main_overlay.dart, ...  # Entry points
├── core/                              # Core services
├── services/
│   ├── ai/ai_service.dart            # AI/LLM integration
│   ├── voice_activation_service.dart  # Wake word detection
│   ├── media/                         # Audio playback
│   ├── firebase_service.dart          # Cloud sync
│   ├── knowledge_graph_service.dart   # Semantic memory
│   ├── dynamic_ambient_service.dart   # Mood system
│   └── ... other services
├── screens/                           # Page widgets
├── widgets/                           # Reusable components
├── models/                            # Data classes
├── voice_provider.dart                # Riverpod providers
├── dev_config.dart                    # Dev API keys (gitignored)
├── constants.dart                     # App constants
└── firebase_options.dart              # Firebase config

test/                     # Unit and widget tests
packages/                 # Custom packages (flutter_overlay_window)
android/, ios/, web/,     # Platform-specific code
windows/, linux/, macos/
```

## 🤖 For Copilot Agents

When working on this project:

1. **Code additions**: Always add to the appropriate service in `lib/services/`, then wire to a Riverpod provider
2. **Testing**: Create tests in `test/` with proper mocking of services
3. **UI Changes**: Keep screens and widgets thin; move complex logic to services
4. **Firebase**: Use `firebase_service` as the single point of Firebase access
5. **Parallel Builds**: Different entry points are built independently; specify `-t` flag
6. **API Keys**: Always use environment variables or `dev_config.dart`, never hardcode in source
7. **Error Handling**: Services handle errors gracefully; providers propagate to UI via widgets
8. **Documentation**: Major features should update relevant `.md` files
9. **Git**: `.gitignore` protects `dev_config.dart` and secure storage

---

**Last Updated**: April 2026  
**Maintain this file** by adding project-specific conventions as they emerge.
