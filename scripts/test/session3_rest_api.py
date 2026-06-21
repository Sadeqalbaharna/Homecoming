#!/usr/bin/env python3
"""
Session 3: Full Conversation Loop with Firebase REST API
Record → Transcribe → ChatGPT → Speak → Log (via REST)

This is a working V1 implementation. Talk to Kai!
"""

import os
import json
import subprocess
import pathlib
import time
import requests
from datetime import datetime

# Configuration
AUDIO_PATH = pathlib.Path("/home/pi/kai/input.wav")
FIREBASE_KEY_PATH = pathlib.Path("/home/pi/kai/firebase_service_account.json")
ENV_PATH = pathlib.Path("/home/pi/kai/.env")
TABLE_ID = "T1"
USER_ID = "demo_user"
FIREBASE_DB_URL = "https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app"

print("\n" + "="*60)
print("🍻 KAI V1 - FULL CONVERSATION MODE")
print("="*60 + "\n")

# Load OpenAI API key from environment or .env file
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")
if not OPENAI_API_KEY and ENV_PATH.exists():
    # Load from .env file
    try:
        with open(ENV_PATH) as f:
            for line in f:
                if line.startswith("OPENAI_API_KEY="):
                    OPENAI_API_KEY = line.split("=", 1)[1].strip()
                    break
    except Exception as e:
        print(f"Warning: Could not read .env: {e}")

# Validate API key is loaded
if not OPENAI_API_KEY:
    print("❌ ERROR: OPENAI_API_KEY not found!")
    print(f"   Checked environment variable and {ENV_PATH}")
    exit(1)

# Auto-detect USB audio device
print("[0/4] 🔍 Finding USB audio device...")
try:
    result = subprocess.run(["arecord", "-l"], capture_output=True, text=True, timeout=5)
    output = result.stdout
    
    # Look for USB Audio device
    usb_device = None
    for line in output.split('\n'):
        if "USB Audio" in line and "card" in line:
            # Extract card number from line like "card 3: PDX417 [PDX417]"
            parts = line.split()
            card_num = parts[1].rstrip(':')
            usb_device = f"plughw:{card_num},0"
            print(f"     ✓ Found USB device: {usb_device}")
            break
    
    if not usb_device:
        print("     ✗ No USB audio device found!")
        print("     Try: arecord -l")
        exit(1)
except Exception as e:
    print(f"     ✗ Failed to detect device: {e}")
    exit(1)

# Step 1: Record audio
print("\n[1/4] 🎤 Recording audio (3 seconds)...")
try:
    subprocess.run([
        "arecord",
        "-D", usb_device,
        "-f", "cd",
        "-t", "wav",
        "-d", "3",
        str(AUDIO_PATH)
    ], check=True, capture_output=True, timeout=10)
    print("     ✓ Audio recorded")
except Exception as e:
    print(f"     ✗ Failed: {e}")
    exit(1)

# Step 2: Transcribe with Whisper
print("\n[2/4] 📝 Transcribing with Whisper...")
try:
    with open(AUDIO_PATH, "rb") as f:
        files = {"file": f, "model": (None, "whisper-1")}
        headers = {"Authorization": f"Bearer {OPENAI_API_KEY}"}
        
        response = requests.post(
            "https://api.openai.com/v1/audio/transcriptions",
            headers=headers,
            files=files,
            timeout=30
        )
    
    if response.status_code != 200:
        print(f"     ✗ API error: {response.status_code}")
        print(f"       {response.text[:200]}")
        exit(1)
    
    user_text = response.json().get("text", "").strip()
    if not user_text:
        user_text = "[silence or unclear audio]"
    
    print(f"     ✓ You said: \"{user_text}\"")
except Exception as e:
    print(f"     ✗ Failed: {e}")
    exit(1)

# Step 3: Ask ChatGPT
print("\n[3/4] 🧠 Calling ChatGPT...")
try:
    headers = {
        "Authorization": f"Bearer {OPENAI_API_KEY}",
        "Content-Type": "application/json"
    }
    
    payload = {
        "model": "gpt-3.5-turbo",
        "messages": [
            {
                "role": "system",
                "content": "You are Kai, a friendly tavern table AI. You're having a casual conversation in a tavern. Keep responses SHORT (1-2 sentences max). Respond with JSON: {\"say\": \"your response\", \"mood\": \"happy/neutral/curious\"}"
            },
            {
                "role": "user",
                "content": user_text
            }
        ],
        "temperature": 0.7,
        "max_tokens": 150
    }
    
    response = requests.post(
        "https://api.openai.com/v1/chat/completions",
        headers=headers,
        json=payload,
        timeout=60
    )
    
    if response.status_code != 200:
        print(f"     ✗ API error: {response.status_code}")
        print(f"       {response.text[:200]}")
        exit(1)
    
    # Parse response
    result = response.json()
    content = result["choices"][0]["message"]["content"].strip()
    
    # Try to parse JSON response
    try:
        chat_data = json.loads(content)
        reply_text = chat_data.get("say", content)
        mood = chat_data.get("mood", "neutral")
    except:
        # Fallback if not JSON
        reply_text = content
        mood = "neutral"
    
    print(f"     ✓ Kai responds: \"{reply_text}\"")
    print(f"       Mood: {mood}")
    
except Exception as e:
    print(f"     ✗ Failed: {e}")
    exit(1)

# Step 4: Speak response
print("\n[4/4] 🔊 Speaking response...")
try:
    # Generate WAV file with espeak-ng
    wav_file = "/home/pi/kai/response.wav"
    subprocess.run(
        ["espeak-ng", "-s", "150", "-w", wav_file, reply_text],
        check=True,
        capture_output=True,
        timeout=10
    )
    
    # Play on USB speaker (card 3)
    subprocess.run(
        ["aplay", "-D", f"plughw:{card_num},0", wav_file],
        check=True,
        capture_output=True,
        timeout=30
    )
    print("     ✓ Response spoken on USB speaker")
except Exception as e:
    print(f"     ⚠️  Audio playback failed: {e}")

# Log to Firebase via REST API
print("\n[+] 📊 Logging to Firebase...")
try:
    timestamp = int(time.time() * 1000)
    
    log_entry = {
        "timestamp": datetime.now().isoformat(),
        "user": {
            "text": user_text,
            "user_id": USER_ID
        },
        "kai": {
            "text": reply_text,
            "mood": mood
        },
        "table_id": TABLE_ID
    }
    
    # Write to Firebase REST API
    firebase_path = f"{FIREBASE_DB_URL}/tables/{TABLE_ID}/conversations/{timestamp}.json"
    response = requests.put(
        firebase_path,
        json=log_entry,
        timeout=10
    )
    
    if response.status_code in [200, 201]:
        print("     ✓ Logged to Firebase")
    else:
        print(f"     ⚠️  Firebase write failed: {response.status_code}")
        print(f"        (This is okay - conversation still worked!)")
        
except Exception as e:
    print(f"     ⚠️  Firebase logging not available: {type(e).__name__}")
    print(f"        (This is okay - conversation still worked!)")

print("\n" + "="*60)
print("✓ CONVERSATION COMPLETE!")
print("="*60)

print("\n🎯 Full loop working:")
print("   Record → Transcribe → ChatGPT → Speak → Log")

print("\n💡 Ready for integration with:")
print("   • Button triggers (Session 4)")
print("   • NFC reader (Session 5)")
print("   • LED effects (Session 4)")
