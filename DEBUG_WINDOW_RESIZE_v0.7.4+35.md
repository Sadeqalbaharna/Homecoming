# Window Resize Debug Build - v0.7.4+35

**Date**: October 20, 2025  
**Issue**: Chat window stuck in top-left corner, not filling screen  
**Status**: 🔍 DEBUGGING

---

## 🐛 Problem

You reported: *"the adaptive window didn't work :/ still just stuck on the top left corner"*

This means:
- Window is positioned at top-left (0,0) ✅
- But window is **NOT resizing** to full screen ❌
- Likely showing small window (200x200 or similar) instead of full device screen

---

## 🔍 Debug Build Features

This version (v0.7.4+35) adds extensive logging to identify the problem:

### Enhanced Logging

```dart
📱 [SCREEN] Physical size: 1080.0x2400.0
📱 [SCREEN] Device pixel ratio: 3.0
📱 [SCREEN] Logical size: 360x800
📱 [SCREEN] Using dimensions: 360x800
📱 [SCREEN] Expanding to FULL SCREEN chat
📱 [SCREEN] Resize result: true/false  ← NEW!
📱 [SCREEN] Move result: true/false    ← NEW!
📱 [SCREEN] ✅ Chat window: 360x800 at (0,0) - FULL SCREEN MODE
```

---

## 📊 What to Check

### Step 1: Install Debug APK

```powershell
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

### Step 2: Connect to Device Logs

```powershell
adb logcat | Select-String "SCREEN"
```

### Step 3: Open Chat and Watch Logs

1. Launch app
2. Tap Kai → Open Chat
3. Watch console output

### Step 4: Analyze Output

Look for these key indicators:

#### ✅ Good Signs
```
📱 [SCREEN] Logical size: 360x800   ← Valid dimensions
📱 [SCREEN] Resize result: true     ← Resize succeeded
📱 [SCREEN] Move result: true       ← Move succeeded
```

#### ❌ Problem Indicators
```
📱 [SCREEN] Logical size: 0x0       ← Invalid dimensions!
📱 [SCREEN] Resize result: false    ← Resize FAILED!
📱 [SCREEN] Move result: false      ← Move FAILED!
```

---

## 🔧 Code Changes in v0.7.4+35

### 1. Round Instead of toInt
```dart
// OLD
final screenWidth = (physicalSize.width / devicePixelRatio).toInt();

// NEW  
final screenWidth = (physicalSize.width / devicePixelRatio).round();
```
**Why**: `round()` is more accurate than `toInt()` for dimensions

### 2. Safe Fallback Dimensions
```dart
final safeWidth = screenWidth > 0 ? screenWidth : 1440;
final safeHeight = screenHeight > 0 ? screenHeight : 3200;
```
**Why**: If calculation fails, use generous defaults that cover most phones

### 3. Resize BEFORE Move
```dart
// OLD order
await FlutterOverlayWindow.moveOverlay(...);
await FlutterOverlayWindow.resizeOverlay(...);

// NEW order
await FlutterOverlayWindow.resizeOverlay(...);  // First resize
await Future.delayed(Duration(milliseconds: 100)); // Wait
await FlutterOverlayWindow.moveOverlay(...);    // Then move
```
**Why**: Some Android versions need delay between operations

### 4. Log Operation Results
```dart
final resized = await FlutterOverlayWindow.resizeOverlay(safeWidth, safeHeight, false);
print('📱 [SCREEN] Resize result: $resized');

final moved = await FlutterOverlayWindow.moveOverlay(const OverlayPosition(0, 0));
print('📱 [SCREEN] Move result: $moved');
```
**Why**: Tells us if operations are actually succeeding

---

## 🧪 Testing Instructions

### Full Debug Session

1. **Connect device via ADB**:
   ```powershell
   adb devices
   ```

2. **Start log monitoring** (in separate terminal):
   ```powershell
   adb logcat -c  # Clear logs
   adb logcat | Select-String -Pattern "SCREEN|flutter"
   ```

3. **Install and launch APK**:
   ```powershell
   adb install -r build\app\outputs\flutter-apk\app-release.apk
   ```

4. **Trigger chat expansion**:
   - Tap Kai avatar
   - Tap Chat button
   - Watch logs in real-time

5. **Copy and share logs**:
   - Look for all `📱 [SCREEN]` messages
   - Share the output so we can diagnose

---

## 🔎 Possible Causes

### Cause 1: Dimension Calculation Failing
**Symptom**: Logs show `0x0` or very small dimensions  
**Fix**: Fallback to 1440x3200 kicks in

### Cause 2: ResizeOverlay Not Working
**Symptom**: `Resize result: false`  
**Fix**: May need to use different overlay approach

### Cause 3: Android Permission Issue
**Symptom**: Operations silently fail  
**Fix**: Check overlay permission in Settings

### Cause 4: Flutter Overlay Window Bug
**Symptom**: resize() doesn't actually resize  
**Fix**: May need to recreate overlay window instead

---

## 📝 Debug Checklist

When you run the app, please check:

- [ ] What dimensions are logged?
  - [ ] Physical size: ______x______
  - [ ] Device pixel ratio: ______
  - [ ] Logical size: ______x______
  - [ ] Using dimensions: ______x______

- [ ] What are the operation results?
  - [ ] Resize result: true / false
  - [ ] Move result: true / false

- [ ] What do you actually see?
  - [ ] Window size (estimate): ______x______
  - [ ] Window position: Top-left / Center / Other
  - [ ] Is window draggable? Yes / No

---

## 🎯 Expected vs Actual

### Expected Behavior
```
1. Tap Chat button
2. Window expands from 200x200 to full screen (e.g., 360x800)
3. Window moves to position (0,0)
4. Window fills entire device screen
5. Chat UI visible edge-to-edge
```

### Current Behavior (Your Report)
```
1. Tap Chat button
2. Window stays small (200x200?)
3. Window stuck at top-left corner
4. Window NOT filling screen
5. Chat UI cramped in small window
```

---

## 🚀 Next Steps

### After Installing v0.7.4+35

1. **Run the app**
2. **Open chat**
3. **Capture the console logs**
4. **Share the output** - specifically:
   - Physical size
   - Logical size
   - Resize result
   - Move result
5. **Take screenshot** of what you see

With this information, I can:
- Identify if dimensions are calculating correctly
- See if resize/move operations are succeeding
- Determine if this is a Flutter overlay limitation
- Implement the correct fix

---

## 📦 Build Info

- **Version**: v0.7.4+35 (Debug Build)
- **APK Size**: 43.7 MB
- **Purpose**: Diagnose window resize failure
- **Location**: `build\app\outputs\flutter-apk\app-release.apk`

---

## 💡 Alternative Approaches (If Current Fails)

If the resize approach doesn't work, we may need to:

1. **Approach A**: Use `FLAG_LAYOUT_IN_SCREEN` flag to force full screen
2. **Approach B**: Create two separate overlay windows (avatar + chat)
3. **Approach C**: Use a Dialog-style overlay instead of window resize
4. **Approach D**: Modify native Android code to handle window dimensions

---

**Please install this debug build and share the console logs so we can identify the exact issue!** 🔍📱
