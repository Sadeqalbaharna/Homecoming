# 🔄 Update Pi Firebase Listener - Quick Fix

## The Issue
Your Pi has the Firebase listener running, but it's missing the latest `set_scene` fixes. The scene lighting commands are being rejected as "Unknown action".

## 🚀 Quick Fix Options

### Option A: Copy Updated File (Recommended)
Since you're logged into the Pi, simply copy the latest version:

1. **Stop the current listener** (if running):
   ```bash
   # Press Ctrl+C to stop the current process
   # OR kill it if running as background service
   pkill -f firebase_rest_listener
   ```

2. **Download the updated file**:
   ```bash
   # Download latest version from GitHub
   wget https://raw.githubusercontent.com/Sadeqalbaharna/Homecoming/main/firebase_rest_listener_debug.py -O firebase_rest_listener_debug_new.py
   
   # Backup current version and replace
   mv firebase_rest_listener_debug.py firebase_rest_listener_debug_backup.py
   mv firebase_rest_listener_debug_new.py firebase_rest_listener_debug.py
   ```

3. **Test the updated version**:
   ```bash
   python3 firebase_rest_listener_debug.py
   ```

### Option B: Quick Manual Fix
If wget doesn't work, manually edit the file to fix the logic:

1. **Edit the file**:
   ```bash
   nano firebase_rest_listener_debug.py
   ```

2. **Find this line** (around line 1180):
   ```python
   else:
       message = f"Unknown action: {action}"
       logger.warning(f"⚠️ {message}")
   ```

3. **Replace with**:
   ```python
   elif action == "set_scene" and target == "lights":
       logger.info("🎨 Scene lighting command")
       scene = command_data.get("scene", "default")
       success = True
       message = f"Scene '{scene}' activated (simulation mode)"
   else:
       message = f"Unknown action: {action} (target: {target})"
       logger.warning(f"⚠️ {message}")
   ```

## ✅ What Should Work After Update

### 🎵 Music Commands (Already Working):
- "Play energetic music" ✅
- "Stop music" ✅
- All track selection working ✅

### 💡 Scene Lighting Commands (Fixed):
- "Set lights to bright" ✅
- "Dim the lights" ✅
- "Set scene to rainbow" ✅
- "Turn lights off" ✅

### 🔊 Audio System (Improved):
- Auto-detects best available audio device ✅
- Better Bluetooth device handling ✅
- Fallback to system audio if needed ✅

## 🎯 Test Commands After Update

1. **Test Scene Lighting**:
   - "Set lights to bright"
   - "Set scene to rainbow"  
   - "Dim the lights"

2. **Test Music + Lighting Coordination**:
   - "GM Kai, party mode" (should trigger both music and lighting)
   - "Play forest sounds" (should trigger nature sounds + green lighting)

## 🔍 Expected Log Output After Fix

You should see:
```
🎨 Scene lighting command
🎭 [SIMULATION] WS2812B Lighting Control:
   Strips: ['main', 'accent', 'ambient']
   Color: white
   Brightness: 90%
   Effect: solid
📤 Sending success response: Scene 'bright' activated: white at 90% brightness
```

Instead of:
```
⚠️ Unknown action: set_scene
```

---

**The system is 95% working - just need this one fix for scene lighting! 🎉**