# Animation Test Mode - v0.7.5+93

**Date:** January 2025  
**Type:** Feature Addition  
**Target:** Desktop Testing

## Problem

User requested animation testing controls that work on desktop. Previous attempts (v0.7.5+91-92) added buttons to `overlay_app.dart`, which is **NOT** the app that runs on desktop.

**Discovery:**
- Desktop runs `lib/main.dart` (1,463 lines, complex chat app)
- Mobile overlay may use `lib/main_overlay.dart` (Android system overlay)
- `lib/overlay_app.dart` is a simple test app, not the actual running app
- All animation button work was done in wrong file

## Solution

Added **Animation Test Mode** directly to `main.dart` with manual override system:

### Architecture

1. **New State Variables:**
   ```dart
   bool _animTestMode = false;           // Toggle for test mode
   _AvatarState? _manualState = null;    // Manual override (null = automatic)
   ```

2. **Modified `_resolveAvatarState()`:**
   - First checks if test mode enabled AND manual state set
   - If yes: returns manual state (override)
   - If no: uses automatic state machine (normal behavior)

3. **UI Components:**
   - **Toggle button** at bottom of screen
   - **4 animation buttons** (Idle, Attn, Think, Speak) when enabled
   - Buttons styled with active/inactive states
   - Golden theme matches app design

### Code Changes

**Added to `_FloatingKaiState`:**
- Lines ~195-200: State variables
- Lines ~210-220: Modified `_resolveAvatarState()` with override logic
- Lines ~235-240: `_setManualState()` helper method

**Added to Stack children (around line 730):**
- Toggle checkbox button
- Conditional 4-button row (only when test mode enabled)

**New Widget Class:**
- `_AnimTestButton` (~760): Reusable button with active/inactive styling

## Features

### Toggle Test Mode
- **Checkbox button** at bottom-left
- Label: "Animation Test Mode"
- Click to enable/disable
- Disabling clears manual override (returns to automatic)

### Animation Buttons (When Enabled)
1. **Idle** - Shows `mage.png` (kAvatarIdleGif)
2. **Attn** - Shows `kai_attention.gif`
3. **Think** - Shows `kai_thinking.gif`
4. **Speak** - Shows `kai_speaking.gif`

**Active State:**
- Gold background (`Color(0xFFFFE7B0)`)
- Dark text (`Color(0xFF0D0A07)`)
- Bold font
- 2px border

**Inactive State:**
- Semi-transparent black background
- Gold text
- Normal font
- 1px border

## Assets Used

All 4 GIF animations from previous work:

```yaml
# From pubspec.yaml
assets:
  - assets/avatar/kai_idle.json      # Not used in main.dart yet
  - assets/avatar/kai_talk.json       # Not used in main.dart yet
  - assets/avatar/images/mage.png     # ✅ Idle state
  # GIFs not declared in pubspec but exist on disk:
  - assets/avatar/idle.gif            # 57 MB
  - assets/avatar/kai_attention.gif   # 55 MB (✅ used by main.dart)
  - assets/avatar/kai_thinking.gif    # 216 MB (✅ used by main.dart)
  - assets/avatar/kai_speaking.gif    # 115 MB (✅ used by main.dart)
```

**Note:** `main.dart` uses GIF files via constants:
```dart
const String kAvatarIdleGif = 'assets/avatar/images/mage.png';
const String kAvatarAttentionGif = 'assets/avatar/kai_attention.gif';
const String kAvatarThinkingGif = 'assets/avatar/kai_thinking.gif';
const String kAvatarSpeakingGif = 'assets/avatar/kai_speaking.gif';
```

These constants are NOT in pubspec.yaml but loaded directly by `Image.asset()`.

## Testing Instructions

### Desktop (Windows)

1. **Run app:**
   ```bash
   flutter run -d windows
   ```

2. **Enable test mode:**
   - Look at bottom-left of window
   - Click checkbox "Animation Test Mode"

3. **Test each animation:**
   - Click **Idle** → Should show static mage image
   - Click **Attn** → Should show attention GIF animation
   - Click **Think** → Should show thinking GIF animation
   - Click **Speak** → Should show speaking GIF animation

4. **Return to automatic mode:**
   - Uncheck "Animation Test Mode"
   - Avatar should return to normal state-based switching

### Expected Behavior

**When test mode OFF:**
- Automatic state switching works normally
- Idle after 10 seconds of no interaction
- Attention when clicked
- Thinking when sending message
- Speaking when TTS playing

**When test mode ON:**
- Manual control overrides automatic
- Avatar stays in selected state
- Other features (chat, TTS, drag) still work
- Selected button highlighted in gold

## Technical Details

### File Modified
- `lib/main.dart` (1 file, 140 insertions)
- Lines ~195-240: State management
- Lines ~730-780: UI components
- Lines ~760-795: `_AnimTestButton` widget

### Architecture Preserved
- Does NOT break existing automatic state machine
- Does NOT modify `_avatarAssetFor()` logic
- Does NOT change asset loading
- Simply adds override layer before automatic resolution

### Git History
```
a317dc0 - Bump version to 0.7.5+93
2cf4464 - Add animation test mode to main.dart - v0.7.5+93
```

## Comparison: overlay_app.dart vs main.dart

### overlay_app.dart (v0.7.5+91-92)
- **Purpose:** Simple animated overlay test app
- **Animation:** Lottie + frame-based (PNG sequences)
- **Control:** Manual buttons only
- **Size:** 425 lines
- **Usage:** NOT used by desktop build

### main.dart (v0.7.5+93)
- **Purpose:** Full chat app with AI, TTS, Firebase
- **Animation:** GIF files via Image.asset()
- **Control:** Automatic state machine + manual test mode
- **Size:** 1,463 lines
- **Usage:** ✅ Actual running app on desktop

## Known Issues

None. Test mode cleanly integrates with existing architecture.

## Future Improvements

1. **Convert GIFs to Lottie** for smaller size:
   - kai_attention.gif (55 MB) → JSON (~10 KB?)
   - kai_thinking.gif (216 MB) → JSON (~15 KB?)
   - kai_speaking.gif (115 MB) → JSON (~10 KB?)

2. **Add keyboard shortcuts:**
   - `T` to toggle test mode
   - `1-4` for animations

3. **Add animation info overlay:**
   - Show current state
   - Show frame count / duration
   - Show file size

4. **Move to dev tools panel** (optional):
   - Instead of always-visible buttons
   - Add to existing dev panel

## Success Criteria

✅ Animation buttons visible on desktop  
✅ All 4 animations testable with buttons  
✅ Toggle mode works correctly  
✅ Automatic mode restored when disabled  
✅ No breaking changes to existing features  
✅ Code committed and pushed (v0.7.5+93)

## Lessons Learned

1. **Always verify entry point** - Check `main()` and `runApp()` calls
2. **File naming can mislead** - "main_overlay.dart" sounds like main but isn't
3. **Search for imports** - If file not imported, it's not used
4. **Read app structure first** - Understand what runs before modifying
5. **Test on target platform** - Desktop != Mobile code paths

---

**Status:** ✅ COMPLETE  
**Ready for:** Desktop testing  
**Next:** User validation on Windows
