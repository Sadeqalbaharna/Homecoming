# ⚠️ 20% VOLUME SAFETY LIMIT - ENFORCED EVERYWHERE

## The Limit is HARDCODED and CANNOT BE EXCEEDED

### Where It's Enforced:

1. **AudioDriver** (`fixtures_v2/drivers/audio_driver.py` lines 162-169)
   ```python
   # Enforce maximum 20% volume for safety in public spaces
   mpv_volume = min(mpv_volume, 20)
   # Ensure minimum 5 for audibility when requested
   mpv_volume = max(mpv_volume, 5)
   ```
   - If you pass `volume=0.8` (80%), it gets capped to `0.20` (20%)
   - If you pass `volume=0.1` (10%), it plays at 10%
   - It CANNOT go above 20% under ANY circumstance

2. **Test Scripts**
   - `test_modular_scene_playback.py` - Explicitly uses `volume: 0.20`
   - `demo_modular_scenes.py` - Shows 20% cap in output
   - `test_bluetooth_tg129c.py` - Documents the safety limit

### Why 20%?

✅ **Prevents hearing damage** - No sudden loud sounds
✅ **Respects others** - Won't disturb people around you in public
✅ **Safe testing** - Can't accidentally play at full volume
✅ **Consistent behavior** - Everyone gets same safe experience

### Testing with 20% Volume

```bash
# All of these will play at maximum 20%:
python test_modular_scene_playback.py haunted_mansion
python test_modular_scene_playback.py dungeon
python test_modular_scene_playback.py forest
```

They all play at **20% or less** - completely safe for public spaces.

### If You Ever Need Higher Volume

⚠️ **Do NOT modify the AudioDriver cap!**

Instead:
1. Move to a private space
2. Use headphones
3. Then increase volume via system settings (separate from app)

The app itself will NEVER output above 20% regardless of what code you write.

---

**Remember:** The code is designed with safety first. The 20% cap cannot be bypassed by accident or forgotten. It's enforced at the driver level, every single time.

✅ **You're safe to test in public at any time.** 🔊
