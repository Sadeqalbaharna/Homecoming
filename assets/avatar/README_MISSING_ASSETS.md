# Avatar Assets

## Current Status (v0.7.5+85)

✅ **Using Lottie Animations** (Preferred Method)
- `kai_idle.json` - Idle animation with breathing and blinking
- `kai_talk.json` - Talking animation

## Missing GIF Files (Optional)

The following GIF animation files are **enabled in pubspec.yaml** but need to be added:

- ✅ `idle.gif` - Available (57.5 MB) - Converted to kai_idle.json
- ❌ `attention.gif` - Not yet added
- ❌ `thinking.gif` - Not yet added  
- ❌ `speaking.gif` - Not yet added

## Recommendations

### Option 1: Convert GIFs to Lottie (RECOMMENDED)
Lottie animations are:
- ✅ Vector-based (sharp at any size)
- ✅ Much smaller file size
- ✅ Better performance
- ✅ Native Flutter support
- ✅ Already working for idle & talk

**To convert:**
1. Use After Effects with Bodymovin plugin
2. Or use online converters like lottiefiles.com
3. Save as `kai_attention.json`, `kai_thinking.json`, `kai_speaking.json`

### Option 2: Add GIF Files
If you have the original GIF files, add them to this folder:
- Use Git LFS for files > 50MB
- Or optimize/compress them first

### Option 3: Extract Frames (Current Method)
Use the included `extract_gif_frames.py` script:
```bash
python extract_gif_frames.py
```
This creates PNG frames for animation (currently used as fallback).

## Original Asset Sizes

```
idle.gif      - 57.5 MB (available)
attention.gif - ~52 MB (needs to be added)
thinking.gif  - ~52 MB (needs to be added)
speaking.gif  - ~110 MB (needs to be added)
```

## App Functionality

The app currently uses:
1. **Primary**: Lottie animations (kai_idle.json, kai_talk.json)
2. **Fallback**: mage.png static image if Lottie fails

No GIF files are required for the app to function properly.