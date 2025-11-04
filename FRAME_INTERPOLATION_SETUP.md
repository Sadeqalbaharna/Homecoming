# 🎬 AI Frame Interpolation Setup Guide

Generate smooth transition frames between Kai's animations using Google's FILM ML model.

## 🚀 Quick Start

### 1. Install Dependencies

```powershell
# Install Python packages
pip install opencv-python numpy tensorflow tensorflow-hub

# Verify installation
python -c "import cv2, numpy, tensorflow, tensorflow_hub; print('✅ All dependencies installed!')"
```

### 2. Run Frame Interpolation

**Batch Process All Transitions (Recommended):**
```powershell
python ai_frame_interpolation.py --batch assets/animations --output transition_frames --count 12 --method film
```

**Single Transition:**
```powershell
python ai_frame_interpolation.py `
  --start assets/animations/idle/frame_0050.png `
  --end assets/animations/attention/frame_0000.png `
  --count 8 `
  --method film
```

## 🎯 What It Does

The script generates smooth bridging frames between Kai's animation states:

- **Idle** → Attention (12 frames)
- **Attention** → Thinking (12 frames)  
- **Thinking** → Speaking (12 frames)
- **Speaking** → Idle (12 frames)

## 🧠 Method Comparison

| Method | Quality | Speed | Use Case |
|--------|---------|-------|----------|
| **FILM** (ML) | ⭐⭐⭐⭐⭐ Excellent | 🐌 Slow (first run) | **Production - Best quality** |
| Optical Flow | ⭐⭐⭐⭐ Very Good | 🚀 Fast | Testing, preview |
| Simple Blend | ⭐⭐ Fair | ⚡ Instant | Quick test only |

**FILM is now the default method** - it produces the smoothest, most natural-looking transitions.

## 📊 Expected Output

```
transition_frames/
├── idle_to_attention/
│   ├── frame_0000.png
│   ├── frame_0001.png
│   ├── ...
│   └── frame_0011.png
├── attention_to_thinking/
│   └── ...
├── thinking_to_speaking/
│   └── ...
└── speaking_to_idle/
    └── ...
```

## 🔧 Advanced Usage

### Adjust Frame Count

More frames = smoother but larger app size:

```powershell
# Silky smooth (16 frames per transition)
python ai_frame_interpolation.py --batch assets/animations --count 16 --method film

# Balanced (8 frames per transition)
python ai_frame_interpolation.py --batch assets/animations --count 8 --method film
```

### Use Different Methods

```powershell
# FILM ML model (best quality, recommended)
--method film

# Optical flow (fast, good quality)
--method optical_flow

# Simple blend (testing only)
--method blend
```

## 🎨 Integration with Flutter

After generating transition frames, you'll need to:

1. **Copy frames to Flutter assets:**
   ```powershell
   Copy-Item transition_frames\* assets\animations\ -Recurse
   ```

2. **Update animation controller** to load transition frames between states

3. **Adjust timing** to play transitions at 60fps

Would you like me to create the Flutter integration code?

## 🐛 Troubleshooting

### "TensorFlow not installed"
```powershell
pip install tensorflow tensorflow-hub
```

### "FILM model download failed"
- Check internet connection
- Model downloads on first run (~200MB)
- Subsequent runs use cached model

### "Out of memory"
- Reduce frame count: `--count 8`
- Process one transition at a time using `--start` and `--end`
- Close other applications

### "Frame size mismatch"
- Script auto-resizes frames to match
- Check source animations are consistent

## 📈 Performance

**First run (FILM):**
- Model download: ~2-3 minutes
- Processing: ~30-60 seconds per transition
- Total: ~5-10 minutes for all 4 transitions

**Subsequent runs:**
- Model cached, no download
- Processing: ~30-60 seconds per transition

**Optical flow (alternative):**
- No download needed
- Processing: ~5-10 seconds per transition

## 🎓 How FILM Works

FILM (Frame Interpolation for Large Motion) is Google's state-of-the-art ML model:

1. **Analyzes motion** between start and end frames
2. **Predicts intermediate pixels** using learned motion patterns
3. **Generates frames recursively** (1→2→4→8→16...)
4. **Handles occlusion** (objects appearing/disappearing)
5. **Preserves details** better than traditional methods

Research paper: https://arxiv.org/abs/2202.04901

## ✨ Results

FILM produces:
- ✅ Natural motion blur
- ✅ Smooth pixel transitions  
- ✅ No ghosting artifacts
- ✅ Handles complex movements
- ✅ Preserves Kai's art style

Perfect for character animation transitions!

## 🚀 Next Steps

1. **Run the script** with FILM method
2. **Review generated frames** in output directory
3. **Test in Flutter** - see transition smoothness
4. **Adjust frame count** if needed (8-16 recommended)
5. **Integrate into app** - update animation controller

---

**Ready to generate smooth transitions?** Run:
```powershell
python ai_frame_interpolation.py --batch assets/animations --output transition_frames --count 12 --method film
```
