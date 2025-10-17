# Developer Mode Guide - Updated for CI/CD Compatibility

## Overview

Developer mode allows you to skip the API key setup screen during development by hardcoding your keys **directly in the source file** for local testing only.

⚠️ **IMPORTANT**: Dev mode is now **inline** in `lib/main_overlay.dart` to ensure CI/CD builds work without external config files.

## Quick Setup (Inline Method)

### 1. Edit main_overlay.dart

Open `lib/main_overlay.dart` and find this section (around line 22):

```dart
// DEV CONFIG - Only available in local development (not in CI/CD)
const bool USE_DEV_MODE = false; // Set to true locally, false in repo
class DevConfig {
  static const String DEV_OPENAI_KEY = '';
  static const String DEV_ELEVENLABS_KEY = '';
  static bool get hasDevKeys => DEV_OPENAI_KEY.isNotEmpty && DEV_ELEVENLABS_KEY.isNotEmpty;
}
```

### 2. Add Your Keys (Locally Only!)

```dart
const bool USE_DEV_MODE = true; // Enable for local dev
class DevConfig {
  static const String DEV_OPENAI_KEY = 'sk-proj-YOUR_ACTUAL_KEY';
  static const String DEV_ELEVENLABS_KEY = 'YOUR_ACTUAL_KEY';
  static bool get hasDevKeys => DEV_OPENAI_KEY.isNotEmpty && DEV_ELEVENLABS_KEY.isNotEmpty;
}
```

### 3. Test Your Build

```powershell
flutter build apk --debug -t lib/main_overlay.dart
adb install build/app/outputs/flutter-apk/app-debug.apk
```

### 4. **CRITICAL**: Revert Before Committing!

```dart
const bool USE_DEV_MODE = false; // Back to false!
class DevConfig {
  static const String DEV_OPENAI_KEY = ''; // Remove your key!
  static const String DEV_ELEVENLABS_KEY = ''; // Remove your key!
  static bool get hasDevKeys => DEV_OPENAI_KEY.isNotEmpty && DEV_ELEVENLABS_KEY.isNotEmpty;
}
```

## Safety Workflow

### Using Git Stash (Recommended)

```powershell
# 1. Edit main_overlay.dart with dev mode enabled + your keys

# 2. Test your changes

# 3. Stash the dev config changes
git stash push -m "dev_keys" lib/main_overlay.dart

# 4. Make your actual code changes

# 5. Commit WITHOUT dev keys
git add .
git commit -m "Your actual changes"

# 6. Restore dev mode for next session
git stash pop
```

### Manual Verification

```powershell
# Before every commit, check:
git diff lib/main_overlay.dart

# Make sure you DON'T see:
# - USE_DEV_MODE = true
# - Your actual API keys
```

## Why This Approach?

**Problem with External `dev_config.dart`:**
- ✅ Secure (in `.gitignore`)
- ❌ Breaks CI/CD builds (file missing in GitHub Actions)
- ❌ Requires special handling

**Solution with Inline Config:**
- ✅ CI/CD builds work (defaults to disabled)
- ✅ Easy to toggle locally
- ⚠️ Requires discipline to not commit keys

## Pre-Commit Hook (Highly Recommended)

Create `.git/hooks/pre-commit`:

```bash
#!/bin/sh
if git diff --cached lib/main_overlay.dart | grep -q "USE_DEV_MODE = true"; then
    echo "❌ ERROR: Dev mode is enabled in main_overlay.dart!"
    echo "Set USE_DEV_MODE = false before committing."
    exit 1
fi

if git diff --cached lib/main_overlay.dart | grep -qE "DEV_OPENAI_KEY = '[^']+'"; then
    echo "❌ ERROR: API keys found in dev config!"
    echo "Remove keys from DevConfig before committing."
    exit 1
fi

echo "✅ Dev config check passed"
```

Make it executable:
```powershell
# On Windows (Git Bash):
chmod +x .git/hooks/pre-commit
```

## What Happens in CI/CD?

When GitHub Actions builds the app:

```dart
// Default state in repo:
const bool USE_DEV_MODE = false; // ← Disabled
class DevConfig {
  static const String DEV_OPENAI_KEY = ''; // ← Empty
  static const String DEV_ELEVENLABS_KEY = ''; // ← Empty
  ...
}
```

Result:
- ✅ Build succeeds
- ✅ App shows setup screen
- ✅ Users enter keys manually
- ✅ Production behavior

## Troubleshooting

### "I accidentally committed my keys!"

```powershell
# 1. Remove from last commit (if not pushed)
git reset HEAD~1

# 2. Edit main_overlay.dart - remove keys, set USE_DEV_MODE = false

# 3. Commit again
git add lib/main_overlay.dart
git commit -m "Your message (keys removed)"

# 4. If already pushed - ROTATE YOUR API KEYS IMMEDIATELY!
# Then force push (coordinate with team first):
git push --force
```

### "Dev mode not working"

1. Verify `USE_DEV_MODE = true`
2. Check keys are not empty strings
3. Uninstall app completely: `adb uninstall com.homecoming.app`
4. Rebuild and reinstall
5. Check logs: `adb logcat -s flutter:I | grep "DEV MODE"`

## Best Practices

**DO:**
- ✅ Use dev mode for local testing only
- ✅ Always revert before committing
- ✅ Use `git diff` before commits
- ✅ Set up pre-commit hook
- ✅ Use git stash for convenience

**DON'T:**
- ❌ Commit with `USE_DEV_MODE = true`
- ❌ Commit your actual API keys
- ❌ Share screenshots showing keys
- ❌ Use production keys in dev mode

## Alternative: Environment Variables (Future Enhancement)

For zero-risk solution, use build-time variables:

```dart
const String? DEV_OPENAI_KEY = String.fromEnvironment('DEV_OPENAI_KEY');
```

Build with:
```powershell
flutter build apk --dart-define=DEV_OPENAI_KEY=your_key
```

This keeps keys completely out of source code.

## Summary

- 🔧 Edit `main_overlay.dart` directly for dev mode
- 🔒 Default is disabled in repo (CI/CD safe)
- ⚠️ **CRITICAL**: Revert before committing
- ✅ Use git stash for convenience
- 🛡️ Set up pre-commit hook for safety
- 🚀 CI/CD builds work without modification

---

**Remember**: With great power comes great responsibility! Always verify your commits don't contain keys.