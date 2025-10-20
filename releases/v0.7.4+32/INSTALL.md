# Quick Installation Guide 📱

## Choose Your Build

### 🤔 Which APK should I install?

**Check your phone:**
- **Modern phone (2018+)**: Use `arm64` version (recommended)
- **Older phone (pre-2018)**: Use `arm32` version

**Which version:**
- **kai-mobile**: Full app with chat interface
- **kai-overlay**: Floating avatar that stays on top

---

## Installation Steps

### 1️⃣ Download APK
Choose one of these files:
- `kai-mobile-v0.7.4+32-arm64.apk` (16.8 MB) ⭐ Recommended
- `kai-mobile-v0.7.4+32-arm32.apk` (14.2 MB)
- `kai-overlay-v0.7.4+32-arm64.apk` (18.2 MB)
- `kai-overlay-v0.7.4+32-arm32.apk` (15.7 MB)

### 2️⃣ Enable Unknown Sources
1. Open **Settings**
2. Go to **Security** or **Privacy**
3. Enable "**Install from Unknown Sources**" or "**Install Unknown Apps**"
4. Select your browser/file manager and allow installations

### 3️⃣ Install
1. Tap the downloaded APK file
2. Tap "**Install**"
3. Wait for installation to complete

### 4️⃣ Grant Permissions
**For Overlay version:**
1. When prompted, tap "**Allow**" for overlay permissions
2. Or go to Settings → Apps → Kai → Display over other apps → Enable

**For both versions:**
- Allow microphone access (for voice input)
- Allow notification access (optional)

### 5️⃣ Setup API Key
**Option A: Dev Mode (Easier)**
- Keys are pre-configured
- Just open the app and start chatting!

**Option B: Your Own Keys**
1. Get OpenAI API key: https://platform.openai.com/api-keys
2. Get ElevenLabs API key: https://elevenlabs.io/
3. Enter keys in the setup screen

---

## First Launch

### Mobile Version
1. Open "**Kai**" from app drawer
2. Chat interface appears
3. Tap microphone to speak or type messages
4. Delta bubbles show personality changes!

### Overlay Version
1. Open "**Kai Overlay**" from app drawer
2. Floating Kai appears on screen
3. Tap avatar to open chat
4. Drag avatar to move it
5. Swipe down to minimize
6. Works on top of other apps!

---

## Testing Memory System

### Quick Test
1. Send 10 messages to Kai
2. Say things like "I love coffee" or "My name is..."
3. Wait 1 hour or send 10 turns
4. Memory shard will be created automatically
5. Facts will be extracted (check Firebase Console)

### Check Memory
Open Firebase Console:
https://console.firebase.google.com/project/homecoming-74f73/database

Look for:
- `/memory/buffers/truekai` - Your conversation buffer
- `/memory/shards/truekai` - Memory segments
- `/memory/facts/truekai` - Extracted knowledge

---

## Troubleshooting

### App won't install
- Make sure "Unknown Sources" is enabled
- Check you have enough storage space (need ~50 MB)
- Try uninstalling old version first

### Overlay not showing
1. Go to Settings → Apps → Kai Overlay
2. Tap "Display over other apps"
3. Enable the permission
4. Restart the app

### No voice input
1. Check microphone permission
2. Go to Settings → Apps → Kai → Permissions
3. Enable Microphone access

### Delta bubbles not appearing
- Delta tracking is automatic!
- Bubbles appear when personality/mood changes
- Look for green (+) or red (-) indicators
- They fade after 1.8 seconds

### Memory not working
1. Check internet connection
2. Verify Firebase Cloud Functions are deployed
3. Run: `.\deploy-kai-brain.ps1`
4. Check Firebase Console for memory data

---

## Updates

### Checking Version
- Open app
- Current version: **v0.7.4+32**

### Getting Updates
- New versions will be posted in releases folder
- Check GitHub: https://github.com/Sadeqalbaharna/Homecoming/releases
- Or Firebase App Distribution (if enrolled)

---

## Features to Try

### 🎭 Delta Tracking
- Watch personality bubbles appear during conversations
- Green = personality trait increased
- Red = personality trait decreased
- Automatic Firebase logging

### 🧠 Memory System
- Kai remembers everything you say
- Ask "What did we talk about?"
- Kai can recall past conversations
- Daily summaries compiled at 2 AM

### 🎤 Voice Input
- Tap microphone button
- Speak naturally
- Kai responds with text (voice coming soon!)

### ⚙️ Customization
- Swipe up for settings (overlay version)
- Adjust avatar size
- Change chat layout
- Configure API keys

---

## Support

### Issues?
- Check Firebase Console for logs
- View function logs: `firebase functions:log`
- Open GitHub issue with error details

### Questions?
- Read full documentation: `KAI_BRAIN_COMPLETE.md`
- Check deployment guide: `KAI_BRAIN_DEPLOYMENT.md`

---

**Enjoy chatting with Kai! 🎉**

Remember: Kai now has long-term memory and learns from every conversation! 🧠✨
