#!/usr/bin/env python3
"""
Kai - Smart Tavern Table (V1 Mission-Aligned)

Core loop:
  1. Wait for trigger (button or NFC)
  2. Record voice (6 sec push-to-talk)
  3. Transcribe with Whisper
  4. Fetch user context from Firebase
  5. Call ChatGPT (JSON-structured output)
  6. Speak reply via TTS
  7. Trigger LED effects
  8. Log to Firebase

This is INTENTIONALLY minimal. No consciousness, no memory neural net, 
no ambiance system. Just: detect → record → ask AI → respond → log.
"""

import json
import time
import subprocess
import pathlib
from datetime import datetime
from typing import Dict, Optional

# --- Firebase ---
import firebase_admin
from firebase_admin import credentials, db

# --- OpenAI ---
from openai import OpenAI

# --- Configuration ---
TABLE_ID = "T1"  # Change for each table
AUDIO_PATH = pathlib.Path("/home/pi/kai/input.wav")
FIREBASE_KEY_PATH = pathlib.Path("/home/pi/kai/firebase_service_account.json")

# Initialize OpenAI (uses OPENAI_API_KEY env var)
client = OpenAI()


def record_audio(seconds: int = 6) -> bool:
    """Record audio from USB microphone."""
    try:
        subprocess.run([
            "arecord",
            "-D", "plughw:1,0",  # USB device (adjust if needed)
            "-f", "cd",           # CD quality (16-bit, 44.1kHz)
            "-t", "wav",
            "-d", str(seconds),
            str(AUDIO_PATH)
        ], check=True, timeout=15)
        return True
    except Exception as e:
        print(f"❌ Recording failed: {e}")
        return False


def transcribe_whisper(path: pathlib.Path) -> Optional[str]:
    """Send audio to Whisper API for transcription."""
    if not path.exists():
        return None
    
    try:
        with open(path, "rb") as f:
            response = client.audio.transcriptions.create(
                model="whisper-1",
                file=f
            )
        return response.text.strip()
    except Exception as e:
        print(f"❌ Transcription failed: {e}")
        return None


def tts_speak(text: str) -> bool:
    """Speak text using local TTS (espeak-ng)."""
    try:
        subprocess.run(
            ["espeak-ng", "-s", "150", text],
            check=True,
            timeout=30
        )
        return True
    except Exception as e:
        print(f"❌ TTS failed: {e}")
        return False


def led_effect(mode: str, color: Optional[str] = None) -> bool:
    """
    Trigger LED effect. Modes: "listening", "thinking", "speaking", "solid"
    
    This calls your LED control script. For V1, just pulse white while thinking.
    """
    try:
        # TODO: Replace with your actual LED controller
        # subprocess.run(["python3", "/home/pi/kai/led_controller.py", mode, color or "white"])
        print(f"🔆 LED: {mode} {color or ''}")
        return True
    except Exception as e:
        print(f"⚠️ LED effect failed: {e}")
        return False


def firebase_init() -> bool:
    """Initialize Firebase Admin SDK."""
    try:
        if not FIREBASE_KEY_PATH.exists():
            print(f"❌ Firebase key not found: {FIREBASE_KEY_PATH}")
            return False
        
        cred = credentials.Certificate(str(FIREBASE_KEY_PATH))
        firebase_admin.initialize_app(cred, {
            "databaseURL": "https://homecoming-kai-default-rtdb.firebaseio.com/"
        })
        print("✓ Firebase initialized")
        return True
    except Exception as e:
        print(f"❌ Firebase init failed: {e}")
        return False


def get_user_context(uid: str) -> Dict:
    """Fetch user profile + history from Firebase for context."""
    try:
        profile = db.reference(f"users/{uid}/profile").get() or {}
        history = db.reference(f"users/{uid}/history").get() or {}
        return {
            "uid": uid,
            "profile": profile,
            "history": history
        }
    except Exception as e:
        print(f"⚠️ Failed to fetch context: {e}")
        return {"uid": uid, "profile": {}, "history": {}}


def call_chatgpt(user_text: str, context: Dict) -> Optional[Dict]:
    """
    Call ChatGPT with structured JSON output.
    
    Response format:
    {
        "say": "What to speak",
        "actions": [{"type": "led", "mode": "solid", "color": "#3a7bd5"}, ...],
        "memory_update": {"key": "value"}  # optional
    }
    """
    system_prompt = (
        "You are Kai, the tavern table AI assistant. "
        "You must ALWAYS respond with ONLY valid JSON (no markdown, no extra text). "
        "Response format: "
        '{"say": "spoken text", "actions": [{"type": "led", ...}], "memory_update": {...}} '
        "Actions can be: {type: 'led', mode: 'solid'|'pulse'|'thinking', color: '#RRGGBB'}"
    )
    
    user_message = (
        f"Table: {TABLE_ID}\n"
        f"User: {context.get('uid', 'unknown')}\n"
        f"User said: {user_text}\n"
        f"Context: {json.dumps(context.get('profile', {}))}"
    )
    
    try:
        response = client.chat.completions.create(
            model="gpt-4-mini",
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_message}
            ],
            temperature=0.7,
            max_tokens=200
        )
        
        # Parse response
        content = response.choices[0].message.content.strip()
        reply = json.loads(content)
        return reply
    except json.JSONDecodeError as e:
        print(f"❌ ChatGPT response was not valid JSON: {e}")
        return None
    except Exception as e:
        print(f"❌ ChatGPT call failed: {e}")
        return None


def apply_actions(actions: list) -> None:
    """Execute actions from ChatGPT response."""
    for action in actions:
        action_type = action.get("type")
        
        if action_type == "led":
            mode = action.get("mode", "solid")
            color = action.get("color", "#ffffff")
            led_effect(mode, color)
        
        elif action_type == "sound":
            cue = action.get("cue", "bell")
            # TODO: Play sound cue
            print(f"🔔 Sound: {cue}")
        
        elif action_type == "relay":
            # TODO: Toggle relay (e.g., under-table light, fogger)
            print(f"⚡ Relay: {action.get('id')}")


def log_event(uid: str, user_text: str, reply: Dict) -> bool:
    """Log conversation to Firebase."""
    try:
        timestamp = datetime.utcnow().isoformat()
        db.reference(f"logs/{TABLE_ID}/{timestamp}").set({
            "uid": uid,
            "user_text": user_text,
            "reply": reply,
            "timestamp": timestamp
        })
        return True
    except Exception as e:
        print(f"⚠️ Failed to log: {e}")
        return False


def run_cycle(uid: str = "demo_user") -> bool:
    """
    Single conversation cycle:
    1. LED: listening pulse
    2. Record audio
    3. Transcribe
    4. Get context
    5. Call ChatGPT
    6. Parse actions
    7. Speak reply
    8. Execute actions
    9. Log event
    """
    print(f"\n🎙️  Listening (6 seconds)...")
    led_effect("listening", "#ffffff")
    
    # Record
    if not record_audio(seconds=6):
        return False
    
    # Transcribe
    user_text = transcribe_whisper(AUDIO_PATH)
    if not user_text:
        print("❌ No speech detected")
        return False
    
    print(f"👂 You said: {user_text}")
    
    # Thinking
    led_effect("thinking", "#ffaa00")
    
    # Get context + call ChatGPT
    context = get_user_context(uid)
    reply = call_chatgpt(user_text, context)
    if not reply:
        tts_speak("Sorry, I didn't understand that.")
        return False
    
    # Apply actions (LEDs, sounds, etc.)
    apply_actions(reply.get("actions", []))
    
    # Speak response
    response_text = reply.get("say", "I heard you.")
    print(f"🤖 Kai says: {response_text}")
    tts_speak(response_text)
    
    # Log
    log_event(uid, user_text, reply)
    
    return True


def main():
    """Main entry point."""
    print("\n" + "="*70)
    print("  🍻 KAI - SMART TAVERN TABLE (V1)")
    print("="*70)
    
    # Initialize
    if not firebase_init():
        print("❌ Firebase not available. Running in demo mode (no persistence).")
    
    print("\nReady. Press button or tap NFC to start conversation.")
    print("(For testing, just call run_cycle() manually)\n")
    
    # For V1: manual trigger
    # TODO: Add GPIO button handler or NFC reader polling
    try:
        while True:
            # In production: wait for GPIO interrupt or NFC
            # For now: run once and wait
            run_cycle(uid="demo_user")
            time.sleep(2)
    except KeyboardInterrupt:
        print("\n\n👋 Goodbye")


if __name__ == "__main__":
    main()
