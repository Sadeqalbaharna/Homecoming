#!/usr/bin/env python3
"""
Session 3 Enhanced: Full Conversation Loop with Context
Record → Log User → Read History & Personality → ChatGPT → Log Response → Speak

This V1 implementation integrates with Firebase for persistent memory and personality tracking.
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
USER_ID = "Darc"  # Changed to match database
FIREBASE_DB_URL = "https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app"

print("\n" + "="*60)
print("🍻 KAI V1 - ENHANCED CONVERSATION MODE")
print("   With Memory & Personality Context")
print("="*60 + "\n")

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

# Auto-detect USB audio device
print("[0/7] 🔍 Finding USB audio device...")
try:
    result = subprocess.run(["arecord", "-l"], capture_output=True, text=True, timeout=5)
    output = result.stdout
    
    usb_device = None
    for line in output.split('\n'):
        if "USB Audio" in line and "card" in line:
            parts = line.split()
            card_num = parts[1].rstrip(':')
            usb_device = f"plughw:{card_num},0"
            print(f"     ✓ Found USB device: {usb_device}")
            break
    
    if not usb_device:
        print("     ✗ No USB audio device found!")
        exit(1)
except Exception as e:
    print(f"     ✗ Failed to detect device: {e}")
    exit(1)

# Step 1: Record audio
print("\n[1/8] 🎤 Recording audio (3 seconds)...")
try:
    subprocess.run([
        "arecord", "-D", usb_device, "-f", "cd", "-t", "wav", "-d", "3",
        str(AUDIO_PATH)
    ], check=True, capture_output=True, timeout=10)
    print("     ✓ Audio recorded")
except Exception as e:
    print(f"     ✗ Failed: {e}")
    exit(1)

# Step 2: Transcribe with Whisper
print("\n[2/8] 📝 Transcribing with Whisper...")
print("     🧠 Sending to AI...")
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
        exit(1)
    
    user_text = response.json().get("text", "").strip()
    if not user_text:
        user_text = "[silence or unclear audio]"
    
    print(f"     ✓ You said: \"{user_text}\"")
except Exception as e:
    print(f"     ✗ Failed: {e}")
    exit(1)

# Step 3: Log user input to Firebase
print("\n[3/8] 📤 Logging user input to Firebase...")
print("     🔄 Connecting...")
user_timestamp = int(time.time() * 1000)
user_log_entry = {
    "timestamp": datetime.now().isoformat(),
    "source": "table_v1",
    "user_id": USER_ID,
    "table_id": TABLE_ID,
    "user_input": user_text
}

try:
    firebase_path = f"{FIREBASE_DB_URL}/conversations/{user_timestamp}-{TABLE_ID}-USER.json"
    response = requests.put(firebase_path, json=user_log_entry, timeout=10)
    if response.status_code in [200, 201]:
        print("     ✓ User input logged")
    else:
        print(f"     ⚠️  Could not log user input: {response.status_code}")
except Exception as e:
    print(f"     ⚠️  Logging failed: {e}")

# Step 4: Read recent conversation history
print("\n[4/8] 📚 Reading conversation history...")
print("     🔍 Searching database...")
conversation_history = []
try:
    # Read last few conversations
    firebase_convos_path = f"{FIREBASE_DB_URL}/conversations.json"
    response = requests.get(firebase_convos_path, timeout=10)
    
    if response.status_code == 200:
        all_convos = response.json()
        if all_convos and isinstance(all_convos, dict):
            # Get last 5 conversations for context
            sorted_keys = sorted(all_convos.keys(), reverse=True)[:10]
            for key in sorted_keys:
                entry = all_convos[key]
                if isinstance(entry, dict):
                    if "user_input" in entry:
                        conversation_history.append(f"User: {entry['user_input']}")
                    elif "content" in entry:
                        conversation_history.append(f"Kai: {entry['content']}")
            
            conversation_history.reverse()
            print(f"     ✓ Retrieved {len(conversation_history)} recent exchanges")
    else:
        print(f"     ⚠️  Could not read history: {response.status_code}")
except Exception as e:
    print(f"     ⚠️  Error reading history: {e}")

# Step 5: Read user personality from Firebase
print("\n[5/8] 🧬 Reading user personality...")
print("     🔍 Loading profile...")
personality_context = ""
try:
    firebase_user_path = f"{FIREBASE_DB_URL}/users/{USER_ID}.json"
    response = requests.get(firebase_user_path, timeout=10)
    
    if response.status_code == 200:
        user_data = response.json()
        if user_data:
            if "personality_summary" in user_data:
                summary = user_data["personality_summary"]
                if "summary" in summary:
                    personality_context = summary["summary"]
                    print(f"     ✓ Loaded user personality")
            elif "mood_current" in user_data:
                mood = user_data["mood_current"]
                personality_context = f"Current mood - Valence: {mood.get('valence', 0)}, Energy: {mood.get('energy', 0)}, Warmth: {mood.get('warmth', 0)}"
                print(f"     ✓ Loaded user mood")
    else:
        print(f"     ⚠️  Could not read personality: {response.status_code}")
except Exception as e:
    print(f"     ⚠️  Error reading personality: {e}")

# Step 6: Ask ChatGPT with context
print("\n[6/8] 🧠 Calling ChatGPT with context...")
print("     💭 Thinking...")
try:
    headers = {
        "Authorization": f"Bearer {OPENAI_API_KEY}",
        "Content-Type": "application/json"
    }
    
    # Build context string
    history_str = "\n".join(conversation_history[-10:]) if conversation_history else "No prior conversation"
    
    system_prompt = f"""You are Kai, a friendly tavern table AI. You're having a casual conversation in a tavern.

IMPORTANT CONTEXT:
1. User Profile: {personality_context if personality_context else 'New user'}
2. Recent conversation history:
{history_str}

Keep responses SHORT (1-2 sentences max). 
Respond with JSON: {{"say": "your response", "mood": "happy/neutral/curious/thoughtful"}}"""
    
    payload = {
        "model": "gpt-3.5-turbo",
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_text}
        ],
        "temperature": 0.7,
        "max_tokens": 150
    }
    
    print("     📤 Sending to OpenAI...")
    response = requests.post(
        "https://api.openai.com/v1/chat/completions",
        headers=headers,
        json=payload,
        timeout=60
    )
    
    if response.status_code != 200:
        print(f"     ✗ API error: {response.status_code}")
        exit(1)
    
    print("     ✓ Received response")
    result = response.json()
    content = result["choices"][0]["message"]["content"].strip()
    
    try:
        chat_data = json.loads(content)
        reply_text = chat_data.get("say", content)
        mood = chat_data.get("mood", "neutral")
    except:
        reply_text = content
        mood = "neutral"
    
    print(f"     ✓ Kai: \"{reply_text}\"")
    print(f"       Mood: {mood}")
    
except Exception as e:
    print(f"     ✗ Failed: {e}")
    exit(1)

# Step 7: Log AI response to Firebase
print("\n[7/8] 📤 Logging Kai's response to Firebase...")
print("     🔄 Saving...")
kai_timestamp = int(time.time() * 1000) + 1  # Ensure different timestamp
kai_log_entry = {
    "timestamp": datetime.now().isoformat(),
    "source": "table_v1",
    "user_id": USER_ID,
    "table_id": TABLE_ID,
    "user_input": user_text,
    "content": reply_text,
    "mood": mood
}

try:
    firebase_path = f"{FIREBASE_DB_URL}/conversations/{kai_timestamp}-{TABLE_ID}-Kai.json"
    response = requests.put(firebase_path, json=kai_log_entry, timeout=10)
    if response.status_code in [200, 201]:
        print("     ✓ Response logged to Firebase")
    else:
        print(f"     ⚠️  Could not log response: {response.status_code}")
except Exception as e:
    print(f"     ⚠️  Logging failed: {e}")

# Step 8: Speak response
print("\n[8/8] 🔊 Speaking response...")
print("     🎵 Generating speech...")
try:
    wav_file = "/home/pi/kai/response.wav"
    subprocess.run(
        ["espeak-ng", "-s", "150", "-w", wav_file, reply_text],
        check=True,
        capture_output=True,
        timeout=10
    )
    
    print("     🔊 Playing audio...")
    subprocess.run(
        ["aplay", "-D", f"plughw:{card_num},0", wav_file],
        check=True,
        capture_output=True,
        timeout=30
    )
    print("     ✓ Response spoken on USB speaker")
except Exception as e:
    print(f"     ⚠️  Audio playback failed: {e}")

print("\n" + "="*60)
print("✓ ENHANCED CONVERSATION COMPLETE!")
print("="*60)

print("\n🎯 Full pipeline working:")
print("   Record → Transcribe → Log → Read History & Personality")
print("   → ChatGPT (with context) → Log → Speak")

print("\n💾 Data logged to Firebase:")
print(f"   User: {user_text}")
print(f"   Kai:  {reply_text}")
print(f"   With personality and history context")
