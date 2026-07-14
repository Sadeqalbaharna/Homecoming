# 🚀 Quick Reference - New Unified Architecture

## The 4 Core Modules

### 📦 `unified_deployment.py`
Deploy anything to Raspberry Pi
```bash
# Auto-discover and deploy
python unified_deployment.py --deploy-files script.py

# Specific IP with tests
python unified_deployment.py --ip 192.168.48.5 --test-audio --test-bluetooth

# Deploy entire directory
python unified_deployment.py --ip 192.168.48.5 --deploy-dir fixtures_v2

# Run remote command
python unified_deployment.py --ip 192.168.48.5 --command "systemctl status kai_home"
```

**Replaces:** deploy_to_pi.py, deploy_on_pi.py, deploy_scene_executor.py, prepare_pi_deployment.py, + 6 more

---

### 🔥 `unified_firebase_listener.py`
Listen to Firebase and execute commands
```bash
# Listen for scenes
python unified_firebase_listener.py --listen-scenes

# Listen for voice commands
python unified_firebase_listener.py --listen-voices

# Start API server
python unified_firebase_listener.py --api-port 5000

# Listen to multiple collections
python unified_firebase_listener.py --listen-scenes --listen-commands --api-port 5000
```

**Replaces:** firebase_listener_300.py, firebase_scene_executor.py, firebase_command_listener.py, + 4 more

---

### 🎵 `unified_voice_music.py`
Analyze voice commands and generate music
```bash
# Test voice analysis
python unified_voice_music.py --test

# Process single command
python unified_voice_music.py --command "play relaxing meditation"

# Use in code
from unified_voice_music import UnifiedVoiceMusic
system = UnifiedVoiceMusic()
result = system.process_command("play upbeat dance music")
print(result['music']['query'])  # "upbeat dance music electronic"
```

**Replaces:** intelligent_kai_music.py, kai_voice_integration.py, voice_enabled_home_automation.py, + 5 more

---

### 🧪 `unified_test_harness.py`
Run comprehensive tests for all systems
```bash
# Run everything
python unified_test_harness.py --all

# Run by category
python unified_test_harness.py --category bluetooth
python unified_test_harness.py --category audio
python unified_test_harness.py --category scene
python unified_test_harness.py --category firebase

# Run single test
python unified_test_harness.py --test "Bluetooth Discovery"
```

**Replaces:** 15+ test_*.py scripts

---

## 📊 Before → After

| Task | Before | After |
|------|--------|-------|
| Deploy to Pi | `python deploy_to_pi.py` | `python unified_deployment.py --ip <IP>` |
| Deploy directory | `python prepare_pi_deployment.py` | `python unified_deployment.py --deploy-dir <DIR>` |
| Start Firebase | `python firebase_listener_300.py &` | `python unified_firebase_listener.py --listen-scenes` |
| Process voice | Multiple imports, 8 files | `from unified_voice_music import UnifiedVoiceMusic` |
| Run tests | Run 15+ separate scripts | `python unified_test_harness.py --all` |

---

## 🎯 Common Scenarios

### Scenario 1: Deploy New Feature to Pi
```bash
# OLD: Multiple commands
scp fixtures_v2 pi@192.168.48.5:~/
scp unified_firebase_listener.py pi@192.168.48.5:~/
ssh pi@192.168.48.5 "cd ~ && python3 unified_firebase_listener.py"

# NEW: One command
python unified_deployment.py --ip 192.168.48.5 --deploy-dir fixtures_v2 --deploy-files unified_firebase_listener.py
```

### Scenario 2: Test Everything
```bash
# OLD: Run multiple test files
python test_bluetooth_tg129c.py
python test_audio_playback.py
python test_firebase_integration.py
python test_modular_scene_playback.py

# NEW: One command
python unified_test_harness.py --all
```

### Scenario 3: Process Voice Command
```bash
# OLD: Import from multiple modules
from intelligent_kai_music import IntelligentKaiMusicSystem
from kai_voice_integration import KaiVoiceWithIntelligentMusic
system = KaiVoiceWithIntelligentMusic()
result = system.handle_voice(command)

# NEW: Single import
from unified_voice_music import UnifiedVoiceMusic
system = UnifiedVoiceMusic()
result = system.process_command(command)
```

### Scenario 4: Start Firebase Listener
```bash
# OLD: Copy from archived version, run directly
python firebase_listener_300.py

# NEW: Clear options
python unified_firebase_listener.py --listen-scenes --api-port 5000
```

---

## 📁 File Organization

**Essential Files:**
```
homecoming_app/
├── unified_deployment.py          ← Deployment
├── unified_firebase_listener.py   ← Firebase
├── unified_voice_music.py         ← Voice/Music
├── unified_test_harness.py        ← Tests
├── cleanup_consolidate.py         ← Archive tool
├── CONSOLIDATION_GUIDE.md         ← Full guide
└── REDUNDANCY_REDUCTION_SUMMARY.md ← This summary
```

**Archived (but available if needed):**
```
ARCHIVED_REDUNDANT/
├── versioned_docs/               ← v0.7.*, v0.8.* docs
├── deployment_scripts/           ← Old deploy_*.py
├── firebase_scripts/             ← Old firebase_*.py
├── voice_music_scripts/          ← Old voice/music
├── test_scripts/                 ← Old test_*.py
├── diagnostic_scripts/           ← Old debug tools
└── MANIFEST.json                 ← What's archived
```

---

## 🔍 Finding What You Need

**Q: I need to deploy something**  
A: Use `unified_deployment.py`

**Q: I need to listen for Firebase changes**  
A: Use `unified_firebase_listener.py`

**Q: I need to process voice commands**  
A: Use `unified_voice_music.py`

**Q: I need to run tests**  
A: Use `unified_test_harness.py`

**Q: I need the old deploy_to_pi.py**  
A: Check `ARCHIVED_REDUNDANT/deployment_scripts/deploy_to_pi.py`

---

## 🎓 Documentation

| Document | Purpose |
|----------|---------|
| `CONSOLIDATION_GUIDE.md` | Detailed migration instructions |
| `REDUNDANCY_REDUCTION_SUMMARY.md` | What was consolidated and why |
| `QUICK_REFERENCE.md` | This file - quick lookup |
| `unified_*.py --help` | CLI help for each module |

---

## ⚡ Pro Tips

1. **Use `--help` on any module:**
   ```bash
   python unified_deployment.py --help
   python unified_firebase_listener.py --help
   python unified_voice_music.py --help
   python unified_test_harness.py --help
   ```

2. **Auto-discover Pi:**
   ```bash
   python unified_deployment.py --deploy-files script.py
   # No --ip needed! It will find the Pi automatically
   ```

3. **Chain operations:**
   ```bash
   python unified_deployment.py --ip 192.168.48.5 \
     --deploy-files unified_firebase_listener.py \
     --deploy-dir fixtures_v2 \
     --test-audio \
     --test-bluetooth
   ```

4. **Use in your code:**
   ```python
   from unified_deployment import PiDeployer
   deployer = PiDeployer(pi_ip="192.168.48.5")
   deployer.deploy_files(["script1.py", "script2.py"])
   deployer.test_audio()
   deployer.test_bluetooth()
   ```

---

## ✅ Consolidation Complete

- ✅ 10+ deployment scripts → 1 module
- ✅ 7+ Firebase listeners → 1 service
- ✅ 8+ voice/music scripts → 1 system
- ✅ 15+ test scripts → 1 harness
- ✅ 100+ documentation files → organized
- ✅ **40-50% code reduction achieved**
- ✅ **Nothing permanently deleted - all archived**

---

**Start here:** [Full Consolidation Guide](CONSOLIDATION_GUIDE.md)
