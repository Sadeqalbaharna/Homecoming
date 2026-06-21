## YouTube Music Integration for Kai v0.8.3+139

### 🎵 NEW FEATURE: YouTube Audio Streaming

Kai can now play any song from YouTube by searching and streaming audio directly to your Pi!

### 🎯 Voice Commands Added

**Basic YouTube Commands:**
- **"Hey Kai, play Bohemian Rhapsody"**
- **"Hey Kai, play Shape of You by Ed Sheeran"**  
- **"Hey Kai, find and play Imagine Dragons Thunder"**
- **"Hey Kai, play some relaxing piano music"**

**Advanced Search Commands:**
- **"Hey Kai, play the latest Taylor Swift song"**
- **"Hey Kai, find classical music by Mozart"**
- **"Hey Kai, search for epic movie soundtracks"**

### 🔧 Technical Implementation

#### Mobile App Changes:
1. **Enhanced AI Detection** - Recognizes YouTube music requests vs ambiance commands
2. **Smart Search Query Extraction** - Parses "play X by Y" format automatically  
3. **Firebase Command Routing** - Sends `play_youtube` commands to Pi

#### Pi Firebase Listener Changes:
1. **YouTube-DLP Integration** - Searches and extracts audio streams
2. **Multi-Tier Audio Fallback** - Bluetooth → Pulse → Default → ALSA
3. **Stream URL Processing** - Direct streaming without downloads

### 📋 Pi Installation Requirements

```bash
# Install YouTube-DLP on Pi
sudo pip3 install yt-dlp --break-system-packages

# OR using apt (preferred)
sudo apt update
sudo apt install yt-dlp

# Verify installation
yt-dlp --version
```

### 🚀 Deployment Steps

1. **Install YouTube-DLP on Pi:**
   ```bash
   ssh pi@192.168.29.5
   sudo pip3 install yt-dlp --break-system-packages
   ```

2. **Deploy updated Firebase listener:**
   ```bash
   # Copy new firebase_rest_listener_debug.py to Pi
   # Restart listener: sudo python3 firebase_rest_listener_debug.py
   ```

3. **Deploy updated mobile app:**
   ```bash
   # Updated ai_service.dart with YouTube detection
   flutter run
   ```

### 🎵 How It Works

```
🎙️ "Hey Kai, play Despacito by Luis Fonsi"
↓
🧠 AI Service detects YouTube music request  
↓
🔍 Extracts search query: "Despacito by Luis Fonsi"
↓
🔥 Firebase: {action: "play_youtube", search_query: "Despacito by Luis Fonsi"}
↓
🍓 Pi: yt-dlp searches YouTube → Gets audio stream URL
↓
🎵 mpv streams audio directly (no download) → 🔊 Speakers
```

### 🎯 Command Processing Logic

#### AI Service Detection:
```dart
// Detects YouTube indicators in Kai's response or user input
final youtubeIndicators = [
  'play song', 'play music', 'search for', 'find and play',
  'song called', 'track called', 'by artist', 'music by'
];
```

#### Firebase Listener Processing:
```python  
elif action == "play_youtube" and target == "music":
    search_query = command_data.get("search_query", "")
    success = self.play_youtube_audio(search_query, voice_analysis)
```

### ✨ Advanced Features

#### Smart Search Extraction:
- **"Play Bohemian Rhapsody by Queen"** → `"Bohemian Rhapsody by Queen"`
- **"Find some jazz music"** → `"jazz music"`
- **"Song called Wonderwall"** → `"Wonderwall"`

#### Audio Quality:
- **Preferred format:** `bestaudio[ext=m4a]/bestaudio[ext=mp3]/bestaudio`
- **Streaming:** Direct mpv streaming (no local storage needed)
- **Fallback system:** Multiple audio device attempts

#### Error Handling:
- **No results found:** Graceful error reporting
- **Stream extraction failure:** Automatic retry with different formats
- **Audio device issues:** Multi-tier fallback system

### 🔊 Audio Pipeline

```
YouTube → yt-dlp → Audio Stream URL → mpv → Audio Device
```

**Audio Device Priority:**
1. Detected Bluetooth device
2. Pulse audio default  
3. System audio default
4. ALSA fallback

### 🎮 Integration with Existing Features

- **Works alongside mood music:** `play_mood` for local tracks, `play_youtube` for searches
- **Maintains ambiance system:** LED lighting still coordinates with music
- **Voice analysis preserved:** Kai's context awareness remains intact
- **Debug logging:** Full YouTube request/response tracking

### 🚀 Testing Commands

Once deployed, test with:

1. **"Hey Kai, play Bohemian Rhapsody"**
2. **"Hey Kai, find some lo-fi hip hop music"**  
3. **"Hey Kai, play the song Blinding Lights by The Weeknd"**
4. **"Hey Kai, search for epic orchestral music"**

### 📊 Expected Results

- **Instant recognition:** AI detects YouTube vs mood requests
- **Fast streaming:** Audio starts within 3-5 seconds  
- **High quality:** Best available audio format from YouTube
- **Robust playback:** Multiple device fallbacks ensure audio works
- **Smart search:** Natural language → YouTube search queries

### 🔧 Troubleshooting

**If YouTube commands don't work:**
```bash
# Check yt-dlp installation
yt-dlp --version

# Test manual search
yt-dlp "ytsearch:test song" --get-url --no-download

# Check Pi logs  
tail -f /var/log/homecoming.log | grep -i youtube
```

**Common issues:**
- **ModuleNotFoundError: yt-dlp** → Install with pip3 or apt
- **No search results** → Check internet connection on Pi
- **Audio device errors** → Check bluetooth/audio setup
- **Stream extraction fails** → YouTube may be blocking, try different query

This transforms Kai from a local music player into a universal music streaming assistant with access to millions of songs! 🎵🚀