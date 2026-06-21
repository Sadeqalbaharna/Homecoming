#!/usr/bin/env python3
"""
Kai V1 Wake Word Listener - Simple Version
Listens continuously and checks if Whisper transcription contains wake word
"""

import os
import subprocess
import sys
import time
import tempfile
import requests
from pathlib import Path

print("\n" + "="*60)
print("🎙️  KAI V1 WAKE WORD LISTENER (Simple)")
print("   Listening for: 'hey kai' or 'kai'")
print("="*60 + "\n")

CONVERSATION_SCRIPT = Path("/home/pi/kai/session3_enhanced.py")
ENV_PATH = Path("/home/pi/kai/.env")
WAKE_WORDS = ["kai", "hey kai", "okay kai"]

# Load OpenAI API key
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")
if not OPENAI_API_KEY and ENV_PATH.exists():
    try:
        with open(ENV_PATH) as f:
            for line in f:
                if line.startswith("OPENAI_API_KEY="):
                    OPENAI_API_KEY = line.split("=", 1)[1].strip()
                    break
    except Exception as e:
        print(f"Warning: Could not read .env: {e}")

if not OPENAI_API_KEY:
    print("❌ ERROR: OPENAI_API_KEY not found!")
    exit(1)

def get_usb_device():
    """Find USB audio device"""
    try:
        result = subprocess.run(["arecord", "-l"], capture_output=True, text=True, timeout=5)
        for line in result.stdout.split('\n'):
            if "USB Audio" in line and "card" in line:
                parts = line.split()
                card_num = parts[1].rstrip(':')
                return f"plughw:{card_num},0"
    except:
        pass
    return None

def record_audio(usb_device, duration=2):
    """Record audio snippet"""
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        wav_path = f.name
    
    try:
        subprocess.run([
            "arecord", "-D", usb_device, "-f", "cd", "-t", "wav", "-d", str(duration),
            wav_path
        ], check=True, capture_output=True, timeout=duration + 5)
        
        return wav_path
    except Exception as e:
        print(f"❌ Recording failed: {e}")
        return None

def transcribe_audio(wav_path):
    """Transcribe audio using Whisper"""
    try:
        with open(wav_path, "rb") as f:
            files = {"file": f, "model": (None, "whisper-1")}
            headers = {"Authorization": f"Bearer {OPENAI_API_KEY}"}
            
            response = requests.post(
                "https://api.openai.com/v1/audio/transcriptions",
                headers=headers,
                files=files,
                timeout=30
            )
        
        if response.status_code == 200:
            text = response.json().get("text", "").strip().lower()
            return text
        else:
            print(f"⚠️  Whisper error: {response.status_code}")
            return None
    
    except Exception as e:
        print(f"⚠️  Transcription failed: {e}")
        return None
    finally:
        # Clean up
        try:
            Path(wav_path).unlink()
        except:
            pass

def check_wake_word():
    """Record and check for wake word"""
    usb_device = get_usb_device()
    if not usb_device:
        print("❌ USB audio device not found")
        return False
    
    # Record short clip
    print("\r🎤 Recording...", end="", flush=True)
    wav_path = record_audio(usb_device, duration=2)
    if not wav_path:
        return False
    
    # Transcribe
    print("\r🧠 Processing...", end="", flush=True)
    text = transcribe_audio(wav_path)
    if not text:
        return False
    
    # Check for wake word
    print(f"\r📝 Heard: '{text}'", end="", flush=True)
    for wake in WAKE_WORDS:
        if wake in text:
            print(f"\n✅ WAKE WORD DETECTED: '{text}'")
            return True
    
    return False

def trigger_conversation():
    """Run the enhanced conversation script"""
    try:
        print("\n💬 STARTING CONVERSATION...")
        result = subprocess.run(
            ["python3", str(CONVERSATION_SCRIPT)],
            cwd="/home/pi/kai",
            timeout=120
        )
        print("\n✅ CONVERSATION COMPLETE\n")
        return result.returncode == 0
    except subprocess.TimeoutExpired:
        print("⚠️  Conversation timeout")
        return False
    except Exception as e:
        print(f"❌ Failed to run conversation: {e}")
        return False

def immediate_relistening():
    """Return to listening immediately without delays"""
    print("", flush=True)  # Clear line
    time.sleep(0.5)  # Brief pause for audio to settle
    print("🎵 Listening (2 second buffer)...", end="", flush=True)

if __name__ == "__main__":
    try:
        print("Starting wake word listener...")
        print("Listening for: 'hey kai', 'kai', 'okay kai'")
        print("Press Ctrl+C to stop\n")
        
        consecutive_fails = 0
        
        while True:
            print("🎵 Listening (2 second buffer)...", end="", flush=True)
            
            if check_wake_word():
                consecutive_fails = 0
                trigger_conversation()
                immediate_relistening()
            else:
                print(" [no match]", end="\r", flush=True)
                consecutive_fails += 1
            
            # If too many failures, restart
            if consecutive_fails > 20:
                print("\n⚠️  Restarting listener...\n")
                consecutive_fails = 0
                time.sleep(2)
    
    except KeyboardInterrupt:
        print("\n\n👋 Listener stopped")
        exit(0)
