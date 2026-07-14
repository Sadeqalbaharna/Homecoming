# 🧠 AI-Powered Music Query Generation - Deployment Guide

## What's New
The Firebase listener has been updated with an intelligent music query generator that dynamically creates YouTube search queries based on the D&D ambiance prompt, instead of using hardcoded queries.

**Old System (Hardcoded):**
```
Prompt: "Warm cozy tavern"
→ Query: "medieval tavern music folk ambient fantasy"
```

**New System (AI-Powered):**
```
Prompt: "Warm cozy tavern with medieval atmosphere"
→ Analysis: environment=tavern, mood=peaceful (from "cozy")
→ Query: "tavern medieval peaceful music ambient"
(Dynamically generated, more contextual)
```

## Deployment Steps

### Step 1: Connect to Pi via SSH
```bash
ssh pi@192.168.2.5
```

### Step 2: Navigate to the listener directory
```bash
cd /home/pi
```

### Step 3: Backup the current listener (safety first!)
```bash
cp firebase_rest_listener_debug.py firebase_rest_listener_debug.py.backup
```

### Step 4: Pull the latest changes from Git
```bash
git pull origin main
```

### Step 5: Kill the running listener
```bash
ps aux | grep firebase_rest_listener
# Copy the PID and run:
sudo kill <PID>
# Or use pkill:
pkill -f firebase_rest_listener
```

### Step 6: Restart the listener
```bash
sudo nohup python3 firebase_rest_listener_debug.py > listener.log 2>&1 &
```

### Step 7: Verify it's running
```bash
ps aux | grep firebase_rest_listener
# Check the log:
tail -f listener.log
```

## Testing the New System

Once the listener is running with the updated code, test it with HTTP requests:

```bash
# Test 1: Tavern Scene
curl -X POST http://localhost:5001/kai/ambiance \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Warm cozy tavern with medieval folk music and hearty ale", "include_music": true}'

# Test 2: Haunted Mansion
curl -X POST http://localhost:5001/kai/ambiance \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Creepy haunted mansion with ghostly whispers and eerie atmosphere", "include_music": true}'

# Test 3: Epic Battle
curl -X POST http://localhost:5001/kai/ambiance \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Epic battle in the dark dungeon with intense combat and spellcasting", "include_music": true}'
```

## What Changed

### 1. **_analyze_ambiance_prompt()** - Enhanced Keyword Detection
- Added more D&D keywords for better scene detection
- Now captures mood indicators like "cozy", "peaceful", "intense"
- Detects intensity preferences from user prompts
- Returns original_prompt in scene_data for logging

### 2. **_get_ambiance_music()** - Intelligent Query Generator
- Replaces hardcoded if/elif chains with smart composition
- Builds queries by combining:
  1. **Action Priority**: Combat spells get "epic", "battle", "intense"
  2. **Environment**: Tavern adds "tavern", "medieval", "folk"
  3. **Mood**: Spooky adds "dark", "ominous", peaceful adds "serene"
  4. **Deduplication**: Removes duplicate words while preserving order
  5. **Fallback**: Adds "fantasy D&D" if query seems incomplete

- Example generated queries from test:
  - "tavern medieval music ambient"
  - "haunted mansion music ambient"
  - "thunderstorm epic dramatic weather music ambient"
  - "epic battle intense orchestral dramatic dungeon underground music"
  - "peaceful serene healing magical glowing castle royal music ambient"

### 3. **Logging Improvements**
- New log entry: "🧠 [MUSIC AI] Generated query from action={action}, env={environment}, mood={mood}: '{query}'"
- Makes it easy to see what the AI generated for each scene

## Verification Checklist

After deployment, verify:

- [ ] Listener starts without errors: `tail -f listener.log`
- [ ] Status endpoint responds: `curl http://192.168.2.5:5001/kai/status`
- [ ] Music queries are logged with 🧠 emoji: `grep "MUSIC AI" listener.log`
- [ ] Test tavern scene plays audio
- [ ] Test haunted mansion scene plays audio
- [ ] Test battle scene plays audio
- [ ] YouTube search results match generated queries

## Rollback (If Needed)

If something goes wrong, quickly rollback:

```bash
cp firebase_rest_listener_debug.py.backup firebase_rest_listener_debug.py
pkill -f firebase_rest_listener
sudo nohup python3 firebase_rest_listener_debug.py > listener.log 2>&1 &
```

## Performance Notes

- Query generation is instant (no API calls needed)
- Music search still uses yt-dlp and YouTube
- No additional dependencies required
- Works with existing Bluetooth speaker setup

## Future Enhancements

Possible improvements (after testing current version):

1. **YouTube Result Scoring**: Pick best result based on prompt relevance, not just #1
2. **AI Query Refinement**: Optional integration with GPT-4o for even smarter queries
3. **Genre Preference Learning**: Remember which queries worked best for each user
4. **Fallback Search**: If first video is bad, automatically try next result

## Questions or Issues?

If the music quality decreases or queries aren't working well:
1. Check the logs: `tail -50 listener.log | grep "MUSIC AI"`
2. Try manual YouTube search with generated query
3. Adjust keyword weights in `action_music_map`, `environment_music_map`, `mood_music_map`
