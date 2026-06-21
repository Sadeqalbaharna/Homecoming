# Secure API Key Management Guide

## ⚠️ Security Warning
**NEVER commit real API keys to Git repositories!** This is a major security risk that can lead to unauthorized usage and billing charges.

## 🔐 Secure Methods for API Keys

### Method 1: Environment Variables (Recommended for Development)

#### Setup Environment Variables

**Windows (PowerShell):**
```powershell
# Set for current session
$env:OPENAI_API_KEY = "your-actual-openai-key-here"
$env:ELEVENLABS_API_KEY = "your-actual-elevenlabs-key-here"

# Set permanently (system-wide)
[Environment]::SetEnvironmentVariable("OPENAI_API_KEY", "your-actual-openai-key-here", "User")
[Environment]::SetEnvironmentVariable("ELEVENLABS_API_KEY", "your-actual-elevenlabs-key-here", "User")
```

**macOS/Linux (Terminal):**
```bash
# Add to ~/.bashrc, ~/.zshrc, or ~/.profile
export OPENAI_API_KEY="your-actual-openai-key-here"
export ELEVENLABS_API_KEY="your-actual-elevenlabs-key-here"

# Reload shell or run:
source ~/.bashrc
```

#### Running with Environment Variables

```bash
# Run Flutter app with environment variables
flutter run --dart-define=OPENAI_API_KEY=your-key-here --dart-define=ELEVENLABS_API_KEY=your-key-here

# Build APK with environment variables  
flutter build apk --release --dart-define=OPENAI_API_KEY=your-key-here --dart-define=ELEVENLABS_API_KEY=your-key-here
```

### Method 2: Local Configuration File (Git-Ignored)

Create a local config file that's never committed to Git:

**1. Add to `.gitignore`:**
```
# API Keys - never commit!
lib/config/api_keys.dart
api_keys.dart
secrets.dart
.env
```

**2. Create `lib/config/api_keys.dart`:**
```dart
// This file is git-ignored and contains real API keys
class LocalApiKeys {
  static const String openaiApiKey = 'your-actual-openai-key-here';
  static const String elevenlabsApiKey = 'your-actual-elevenlabs-key-here';
}
```

**3. Update AI Service to use local config:**
```dart
import 'package:homecoming_app/config/api_keys.dart' as local;

class AIConfig {
  static const String openaiApiKey = local.LocalApiKeys.openaiApiKey;
  static const String elevenlabsApiKey = local.LocalApiKeys.elevenlabsApiKey;
}
```

### Method 3: Flutter Secure Storage (Production Recommended)

For production apps, use secure device storage:

**1. Add dependency to `pubspec.yaml`:**
```yaml
dependencies:
  flutter_secure_storage: ^9.0.0
```

**2. Implement secure storage:**
```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureApiKeys {
  static const _storage = FlutterSecureStorage();
  
  static Future<String?> getOpenAIKey() async {
    return await _storage.read(key: 'openai_api_key');
  }
  
  static Future<void> setOpenAIKey(String key) async {
    await _storage.write(key: 'openai_api_key', value: key);
  }
  
  static Future<String?> getElevenLabsKey() async {
    return await _storage.read(key: 'elevenlabs_api_key');
  }
  
  static Future<void> setElevenLabsKey(String key) async {
    await _storage.write(key: 'elevenlabs_api_key', value: key);
  }
}
```

### Method 4: Remote Configuration (Firebase Remote Config)

For apps distributed to users, use Firebase Remote Config:

**1. Setup Firebase Remote Config**
**2. Store API keys in Firebase Console**
**3. Fetch keys at runtime**

```dart
import 'package:firebase_remote_config/firebase_remote_config.dart';

class RemoteApiKeys {
  static late FirebaseRemoteConfig _remoteConfig;
  
  static Future<void> initialize() async {
    _remoteConfig = FirebaseRemoteConfig.instance;
    await _remoteConfig.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(minutes: 1),
      minimumFetchInterval: const Duration(hours: 1),
    ));
    await _remoteConfig.fetchAndActivate();
  }
  
  static String get openaiApiKey => _remoteConfig.getString('openai_api_key');
  static String get elevenlabsApiKey => _remoteConfig.getString('elevenlabs_api_key');
}
```

## 🚀 Current Implementation

Your app now uses environment variables:

```dart
class AIConfig {
  static const String openaiApiKey = String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');
  static const String elevenlabsApiKey = String.fromEnvironment('ELEVENLABS_API_KEY', defaultValue: '');
}
```

## 🛠️ How to Use

### Development:
1. Set environment variables on your system
2. Run: `flutter run --dart-define=OPENAI_API_KEY=your-key`

### Production APK:
1. Build with: `flutter build apk --release --dart-define=OPENAI_API_KEY=your-key --dart-define=ELEVENLABS_API_KEY=your-key`

### CI/CD (GitHub Actions):
Store secrets in GitHub repository settings and use them in workflows:

**Setting up GitHub Secrets:**
1. Go to your repository on GitHub
2. Click Settings → Secrets and variables → Actions  
3. Click "New repository secret"
4. Add:
   - Name: `OPENAI_API_KEY`, Value: your OpenAI API key
   - Name: `ELEVENLABS_API_KEY`, Value: your ElevenLabs API key

**GitHub Actions Workflow:**
```yaml
- name: Build APK
  run: |
    flutter build apk --release \
      --dart-define=OPENAI_API_KEY=${{ secrets.OPENAI_API_KEY }} \
      --dart-define=ELEVENLABS_API_KEY=${{ secrets.ELEVENLABS_API_KEY }}
```

**✅ Your Repository Now Has:**
- Automated APK builds with secure API keys
- Manual build triggers via GitHub Actions
- Automatic releases with APK downloads
- Web builds for hosting

## 📱 For Phone Installation

When building for your phone, include the keys in the build command:

```bash
flutter build apk --release --dart-define=OPENAI_API_KEY=sk-your-key --dart-define=ELEVENLABS_API_KEY=your-elevenlabs-key
```

## 🔒 Security Best Practices

### For Cloud Functions (.env files)

**Q: Is `functions/.env` safe?**  
**A: YES! ✅** It's secure and industry-standard because:

1. **Protected by `.gitignore`** - The file is automatically excluded from Git commits
   ```
   # functions/.gitignore
   .env  ← This prevents .env from being committed to Git
   ```

2. **Local-Only** - The `.env` file only exists on your development machine, never in GitHub

3. **Industry Standard** - Used by millions of developers (dotenv has 40M+ weekly downloads)

4. **Automatically Cleaned** - GitHub Actions creates `.env` temporarily during deployment, then deletes it

**Verification:**
```powershell
# Check .gitignore protection
Get-Content functions\.gitignore
# Should show: .env

# Verify .env is ignored
git status
# .env should NOT appear (even if file exists)
```

**Safe Workflow:**
```powershell
# 1. Create .env locally (safe - gitignored)
"OPENAI_API_KEY=sk-proj-YOUR_KEY" | Out-File functions\.env -Encoding utf8

# 2. Deploy
firebase deploy --only functions

# 3. Push to GitHub (production uses GitHub Secrets instead)
git push origin main
```

**What's NOT Safe:**
- ❌ Hardcoding keys in source code (exposed in Git)
- ❌ Using `git add -f functions/.env` (bypasses .gitignore)
- ❌ Removing `.env` from `.gitignore`

### General Security

1. **Never commit real API keys to Git**
2. **Use environment variables for development**
3. **Use secure storage for production apps**
4. **Rotate keys regularly**
5. **Monitor API usage for unusual activity**
6. **Use least-privilege API permissions**
7. **Consider server-side proxy for sensitive operations**

## ⚡ Quick Start

1. Get your API keys:
   - OpenAI: https://platform.openai.com/api-keys
   - ElevenLabs: https://elevenlabs.io/app/speech-synthesis

2. Set environment variables (see platform instructions above)

3. Run the app:
   ```bash
   flutter run --dart-define=OPENAI_API_KEY=your-key-here
   ```

Your API keys are now secure and won't be exposed in your repository!