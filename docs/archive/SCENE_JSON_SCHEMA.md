# Homecoming Kai Scene JSON Schema

## Overview
Complete structured format for scene prompts that flow from mobile voice command → ChatGPT → Firebase → Pi execution.

---

## Complete Scene JSON Structure

```json
{
  "id": "scene_20260107_143022_haunted_tavern",
  "metadata": {
    "created_at": 1704975622,
    "user_id": "kai_companion",
    "original_command": "create a spooky tavern where adventurers gather for a mystery",
    "source": "mobile_voice_command",
    "version": "1.0"
  },
  "scene": {
    "name": "Haunted Tavern",
    "type": "tavern",
    "mood": "spooky",
    "description": "A mysterious tavern shrouded in shadow with flickering candlelight, ghostly whispers, and an air of danger. Strange patrons gather in the corners, and the floorboards creak ominously.",
    "intensity": 0.7,
    "duration_seconds": 300
  },
  "audio": {
    "enabled": true,
    "type": "youtube_search",
    "query": "haunted tavern D&D ambiance music",
    "stream_url": null,
    "volume_percent": 20,
    "fade_in_seconds": 2,
    "fade_out_seconds": 3,
    "loop": true
  },
  "lighting": {
    "enabled": true,
    "strips": [
      {
        "name": "main",
        "animation": "flicker",
        "colors": [
          {"r": 139, "g": 69, "b": 19, "intensity": 0.6},
          {"r": 180, "g": 82, "b": 45, "intensity": 0.5},
          {"r": 101, "g": 50, "b": 16, "intensity": 0.4}
        ],
        "speed": 0.3,
        "brightness": 150
      }
    ],
    "transition_seconds": 1
  },
  "devices": {
    "bluetooth_speaker": {
      "enabled": true,
      "device_name": "TG-129C",
      "sink_name": "bluez_output.39_3E_58_14_40_4A.1"
    },
    "led_strips": {
      "enabled": true,
      "count": 300
    }
  },
  "execution": {
    "status": "pending",
    "started_at": null,
    "completed_at": null,
    "error": null
  },
  "mobile_callback": {
    "send_status_updates": true,
    "send_completion": true
  }
}
```

---

## Field Descriptions

### `metadata`
| Field | Type | Purpose |
|-------|------|---------|
| `id` | string | Unique identifier: `scene_[YYYYMMDD]_[HHMMSS]_[type]` |
| `created_at` | timestamp | Unix timestamp when scene was generated |
| `user_id` | string | User who initiated command |
| `original_command` | string | Exact voice command from user |
| `source` | string | Origin: `mobile_voice_command`, `api_call`, `scheduled`, etc. |
| `version` | string | Schema version for future compatibility |

### `scene`
| Field | Type | Purpose |
|-------|------|---------|
| `name` | string | Human-readable scene name |
| `type` | string | Category: `tavern`, `dungeon`, `forest`, `battle`, `custom` |
| `mood` | string | Emotional tone: `spooky`, `epic`, `relaxing`, `mysterious`, `chaotic` |
| `description` | string | Detailed scene narrative (100-300 chars) |
| `intensity` | float | 0.0-1.0 scale of sensory intensity |
| `duration_seconds` | int | How long scene runs (0 = infinite) |

### `audio`
| Field | Type | Purpose |
|-------|------|---------|
| `enabled` | bool | Whether to play audio |
| `type` | string | `youtube_search` (queries YouTube), `stream_url` (direct URL), `local_file` |
| `query` | string | YouTube search query (used if type=`youtube_search`) |
| `stream_url` | string | Direct HLS/stream URL (populated by yt-dlp or preset) |
| `volume_percent` | int | 0-20 (20% max safety limit) |
| `fade_in_seconds` | float | Ramp up volume over N seconds |
| `fade_out_seconds` | float | Ramp down volume over N seconds |
| `loop` | bool | Whether audio repeats |

### `lighting`
| Field | Type | Purpose |
|-------|------|---------|
| `enabled` | bool | Whether to control LEDs |
| `strips[].name` | string | LED strip identifier (`main`, `ambient`, `accent`) |
| `strips[].animation` | string | `solid`, `flicker`, `pulse`, `wave`, `rainbow`, `strobe` |
| `strips[].colors` | array | RGB color palette for animation |
| `strips[].speed` | float | Animation speed multiplier (0.1-2.0) |
| `strips[].brightness` | int | 0-255 LED brightness |
| `transition_seconds` | float | Fade time when changing lighting |

### `devices`
| Field | Type | Purpose |
|-------|------|---------|
| `bluetooth_speaker.enabled` | bool | Use Bluetooth speaker |
| `bluetooth_speaker.device_name` | string | Speaker model (`TG-129C`) |
| `bluetooth_speaker.sink_name` | string | PulseAudio sink name |
| `led_strips.enabled` | bool | Use LED strips |
| `led_strips.count` | int | Number of addressable LEDs |

### `execution`
| Field | Type | Purpose |
|-------|------|---------|
| `status` | string | `pending` → `executing` → `completed` or `error` |
| `started_at` | timestamp | When Pi began execution |
| `completed_at` | timestamp | When scene finished |
| `error` | string | Error message if execution failed |

### `mobile_callback`
| Field | Type | Purpose |
|-------|------|---------|
| `send_status_updates` | bool | Push status to mobile during execution |
| `send_completion` | bool | Notify mobile when scene completes |

---

## Example Scenes

### Example 1: Spooky Haunted Mansion
```json
{
  "scene": {
    "name": "Haunted Mansion",
    "type": "tavern",
    "mood": "spooky",
    "description": "Ghostly whispers echo through shadowed halls",
    "intensity": 0.8,
    "duration_seconds": 300
  },
  "audio": {
    "query": "haunted mansion spooky ambiance music",
    "volume_percent": 20
  },
  "lighting": {
    "strips": [{
      "animation": "flicker",
      "colors": [
        {"r": 60, "g": 60, "b": 100},
        {"r": 30, "g": 30, "b": 50}
      ],
      "speed": 0.4
    }]
  }
}
```

### Example 2: Epic Battle
```json
{
  "scene": {
    "name": "Epic Battle",
    "type": "battle",
    "mood": "epic",
    "description": "Intense combat with clashing steel and heroic fanfares",
    "intensity": 0.9,
    "duration_seconds": 600
  },
  "audio": {
    "query": "epic battle D&D combat music",
    "volume_percent": 20
  },
  "lighting": {
    "strips": [{
      "animation": "strobe",
      "colors": [
        {"r": 255, "g": 0, "b": 0},
        {"r": 255, "g": 165, "b": 0}
      ],
      "speed": 1.5
    }]
  }
}
```

### Example 3: Relaxing Forest
```json
{
  "scene": {
    "name": "Enchanted Forest",
    "type": "forest",
    "mood": "relaxing",
    "description": "Peaceful woodland with gentle wildlife sounds",
    "intensity": 0.4,
    "duration_seconds": 0
  },
  "audio": {
    "query": "peaceful forest nature ambiance",
    "volume_percent": 15
  },
  "lighting": {
    "strips": [{
      "animation": "pulse",
      "colors": [
        {"r": 34, "g": 139, "b": 34},
        {"r": 144, "g": 238, "b": 144}
      ],
      "speed": 0.2
    }]
  }
}
```

---

## Firebase Collection Structure

**Path:** `scene_prompts/{sceneId}`

### Firestore Indexes Needed
```
- timestamp (descending)
- user_id + status
- scene.type + created_at
```

### Real-time Listener Triggers
Pi will listen to:
```
scene_prompts/{sceneId}
WHERE status == "pending" AND devices.led_strips.enabled == true
```

---

## Flow: Voice Command → JSON

**User:** "Create a spooky tavern for treasure hunters gathering"

**Step 1 - Mobile Transcription:**
```
Audio → OpenAI Whisper → "Create a spooky tavern for treasure hunters gathering"
```

**Step 2 - ChatGPT Generation:**
```
Input: "Create a spooky tavern for treasure hunters gathering"
ChatGPT Prompt: "Generate a D&D scene JSON where..."
Output: Complete scene JSON (above structure)
```

**Step 3 - Firebase Storage:**
```
POST /scene_prompts/scene_20260107_143022_haunted_tavern
  → JSON stored with status="pending"
```

**Step 4 - Pi Listener:**
```
Firestore onSnapshot() detects new "pending" scene
→ Executes lighting + audio
→ Updates status="executing"
→ Updates status="completed"
```

**Step 5 - Mobile Notification:**
```
Mobile listens to same document
→ Sees status changes
→ Updates UI: "Tavern scene activated ✓"
```

---

## Animation Types Reference

| Animation | Effect | Use Case |
|-----------|--------|----------|
| `solid` | Constant color | Background atmosphere |
| `flicker` | Random flicker | Candlelight, fire, ghosts |
| `pulse` | Breathing fade | Heartbeat, magic, breathing |
| `wave` | Color wave traveling | Water, energy, motion |
| `rainbow` | RGB cycling | Celebration, magic |
| `strobe` | On/off rapid | Combat, danger, alarm |

---

## Notes for Implementation

1. **Volume Cap**: Audio always capped at 20% (enforced in AudioDriver)
2. **Stream URL**: Initially null. yt-dlp fills it at runtime when Pi receives scene
3. **Status Machine**: `pending` → `executing` → `completed` (or `error`)
4. **Mobile Sync**: Dart app listens to same Firebase document for real-time updates
5. **Fallback Handling**: If YouTube search fails, fallback to local audio files or silence
6. **Duration**: 0 = infinite (user must manually stop), >0 = auto-stop after N seconds
