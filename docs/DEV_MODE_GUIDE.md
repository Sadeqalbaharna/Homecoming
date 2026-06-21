# Development Mode Guide

## Skip API Key Input During Development

When you're building and testing frequently, entering API keys every time is annoying. Here's how to skip it:

### Quick Setup (One-Time)

1. **Open `lib/dev_config.dart`**

2. **Add your API keys:**
   ```dart
   const bool USE_DEV_MODE = true;  // Change to true
   
   class DevConfig {
     static const String DEV_OPENAI_KEY = 'sk-your-actual-key-here';
     static const String DEV_ELEVENLABS_KEY = 'your-elevenlabs-key-here';
   }
   ```

3. **Build and run:**
   ```powershell
   flutter build apk --debug -t lib/main_overlay.dart
   ```

4. **That's it!** The app will now auto-populate API keys on every fresh install.

### How It Works

- When `USE_DEV_MODE = true`, the app automatically saves your hardcoded keys to secure storage on startup
- You'll skip the API key setup screen entirely
- Keys persist between app restarts (just like normal)
- Only lost when you **uninstall** the app - but dev mode auto-restores them!

### Before Distribution

**IMPORTANT:** Before pushing to Firebase Distribution or production:

1. Set `USE_DEV_MODE = false` in `lib/dev_config.dart`
2. Build release version
3. This ensures real users see the secure setup screen

### Security Notes

- ✅ `lib/dev_config.dart` is in `.gitignore` - won't be committed
- ✅ Keys are still stored securely in Android Keystore
- ✅ Dev mode only affects initial population, not storage mechanism
- ⚠️ **Never commit real API keys to git**
- ⚠️ **Always disable dev mode before distributing**

### Why This Helps

During development, you:
- Uninstall/reinstall frequently → Loses secure storage
- Test on emulators → Fresh storage every time
- Iterate quickly → Entering keys 20+ times per day is painful

Dev mode solves this by auto-restoring keys on each install!
