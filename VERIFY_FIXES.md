# Verify Fixes Are Working

## ⚠️ CRITICAL: You MUST rebuild the app!

The fixes are in the code, but you need to rebuild:

```powershell
# Stop the app
# Then rebuild
flutter run
```

OR if using Android/iOS:
```powershell
flutter run -d <device-id>
```

---

## 🎤 Voice Self-Hearing Fix Verification

### What to look for in console:

When Kai speaks, you should see:
```
🔇 [MAIN] Audio playing - PAUSING voice activation
⏸️ [VoiceActivation] Paused listening (Kai speaking)
```

When audio finishes, you should see:
```
🔊 [MAIN] Audio stopped/completed - RESUMING voice activation
⏱️ [VoiceActivation] Scheduling resume in 2000ms (buffer delay)
▶️ [VoiceActivation] Resumed listening (paused for XXXXms)
```

### If you DON'T see these logs:
1. The app wasn't rebuilt with the new code
2. Voice activation is disabled
3. Audio is playing from a different source

### Test procedure:
1. Enable voice activation
2. Say "Hey Kai, how are you?"
3. Wait for Kai to respond with voice
4. **Watch console** - you should see pause/resume logs
5. Kai should NOT respond to his own voice
6. After 2 seconds of silence, voice activation resumes

---

## 🗺️ Mind Map Fix Verification

### What to test:

1. Open mind map
2. You should see a **RED floating button** in bottom-right corner
3. Even if screen is gray/stuck/loading, button should be visible
4. Click button → should close mind map immediately

### What to look for in console:

When opening mind map:
```
🗺️ [MindMap] initState called for personaId: truekai
🗺️ [MindMap] Starting graph load...
🗺️ [MindMap] _loadGraph started
🗺️ [MindMap] Loading state set, isLoading: true
🗺️ [MindMap] Calling buildGraph with personaId: truekai
🗺️ [MindMap] buildGraph returned with X nodes and Y edges
```

If it takes >10 seconds:
```
❌ [MindMap] Loading timeout - Firebase may be slow or offline
```

When clicking red exit button:
```
🚪 [MindMap] Emergency exit button pressed
```

### If mind map is gray with no button:
The app wasn't rebuilt! The changes ARE in the code.

---

## 🔍 Quick Verification Checklist

After pulling latest code:

- [ ] Run `git log --oneline -3` - should show commit `5d466b6` (voice fix)
- [ ] Run `git status` - should say "up to date with origin/main"
- [ ] **STOP the running app completely**
- [ ] Run `flutter clean` (optional but recommended)
- [ ] Run `flutter pub get`
- [ ] Run `flutter run` to rebuild
- [ ] Test voice - watch for pause/resume logs
- [ ] Test mind map - see red exit button

---

## 🐛 Still Not Working?

### Check these:

1. **Did you rebuild?**
   - Just pulling code isn't enough
   - You MUST stop and restart the app
   - The old running app won't have the changes

2. **Is voice activation enabled?**
   ```dart
   // Check in console when app starts
   ✅ [VoiceActivation] Started listening for "Hey Kai"
   ```

3. **Are you on the right branch?**
   ```powershell
   git branch  # Should show "* main"
   git log --oneline -1  # Should show 5d466b6 or newer
   ```

4. **Check imports compile correctly:**
   ```powershell
   flutter analyze
   # Should show no errors in:
   # - lib/main.dart
   # - lib/voice_controller.dart
   # - lib/widgets/expanded_window.dart
   # - lib/screens/mind_map_screen.dart
   ```

5. **Are multiple audio players active?**
   - The fix covers: main.dart, expanded_window.dart, voice_controller.dart
   - If you have other audio players, they need the same fix

---

## 📱 Testing on Different Platforms

### Windows Desktop:
- main.dart controls the main audio player ✅
- expanded_window.dart for chat history replay ✅
- voice_controller.dart might not be used ✅

### Android/iOS:
- All three audio players may be active
- Check which one is actually playing TTS
- Look for the pause/resume logs to confirm

---

## 🚨 Emergency Debug

If STILL not working, add more logging:

### In `lib/services/voice_activation_service.dart`:

Check that the resume buffer delay is actually 2000ms:
```dart
static const Duration _resumeBufferDelay = Duration(milliseconds: 2000);
```

If Kai still responds to himself, try increasing it:
```dart
static const Duration _resumeBufferDelay = Duration(milliseconds: 3000); // 3 seconds
```

### To verify pause is being called:

When Kai speaks, manually check:
```dart
print('Voice activation isPaused: ${VoiceActivationService()._isPaused}');
```

(Note: _isPaused is private, so you'd need to add a public getter)

---

## ✅ Success Indicators

### Voice fix is working when:
- ✅ You see "PAUSING voice activation" when audio plays
- ✅ You see "RESUMING voice activation" 2s after audio stops
- ✅ Kai does NOT respond to his own voice
- ✅ You CAN trigger Kai again after 2s buffer

### Mind map fix is working when:
- ✅ You see red floating button immediately
- ✅ Button works even during gray screen
- ✅ Console shows debug logs during loading
- ✅ Timeout triggers after 10s if Firebase is slow

---

## 🔄 Final Steps

1. Pull latest: `git pull`
2. Check commit: `git log --oneline -1` → should be `5d466b6` or newer
3. **REBUILD**: Stop app, run `flutter run`
4. Test voice: Say "Hey Kai" → watch console for pause/resume
5. Test mind map: Open it → see red button
6. Report back with console output if still failing

The fixes ARE in the code. They just need to be built and run!
