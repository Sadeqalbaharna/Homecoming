#!/usr/bin/env python3
"""
Simple V1 test - record audio and send to Whisper
"""
import os
import json
import subprocess
import pathlib
import time

AUDIO_PATH = pathlib.Path("/home/pi/kai/input.wav")
API_KEY = os.environ.get("OPENAI_API_KEY", "")

print("\n🍻 KAI V1 - Session 2 Test")
print("=" * 50)

# Test 1: Audio recording
print("\n[1/3] Testing audio recording...")
try:
    result = subprocess.run([
        "arecord",
        "-D", "plughw:1,0",
        "-f", "cd",
        "-t", "wav",
        "-d", "3",
        str(AUDIO_PATH)
    ], check=True, capture_output=True, timeout=10)
    
    if AUDIO_PATH.exists():
        size = AUDIO_PATH.stat().st_size
        print(f"✓ Audio recorded: {size} bytes")
    else:
        print("✗ Audio file not created")
except Exception as e:
    print(f"✗ Recording failed: {e}")
    exit(1)

# Test 2: Firebase credentials
print("\n[2/3] Testing Firebase credentials...")
firebase_key = pathlib.Path("/home/pi/kai/firebase_service_account.json")
if firebase_key.exists():
    try:
        with open(firebase_key) as f:
            creds = json.load(f)
        project_id = creds.get("project_id", "unknown")
        print(f"✓ Firebase key loaded (project: {project_id})")
    except Exception as e:
        print(f"✗ Firebase key invalid: {e}")
        exit(1)
else:
    print("✗ Firebase key not found")
    exit(1)

# Test 3: OpenAI API
print("\n[3/3] Testing OpenAI Whisper API...")
if not API_KEY:
    print("✗ OPENAI_API_KEY not set")
    exit(1)

try:
    import requests
    with open(AUDIO_PATH, "rb") as f:
        files = {"file": f, "model": (None, "whisper-1")}
        headers = {"Authorization": f"Bearer {API_KEY}"}
        
        print("  → Sending to Whisper API...")
        response = requests.post(
            "https://api.openai.com/v1/audio/transcriptions",
            headers=headers,
            files=files,
            timeout=30
        )
    
    if response.status_code == 200:
        data = response.json()
        text = data.get("text", "")
        print(f"✓ Transcription: {text[:60]}..." if len(text) > 60 else f"✓ Transcription: {text}")
    else:
        print(f"✗ API error: {response.status_code}")
        print(f"  {response.text[:200]}")
        exit(1)
        
except Exception as e:
    print(f"✗ API test failed: {e}")
    exit(1)

print("\n" + "=" * 50)
print("✓ Session 2 - All tests PASSED!")
print("=" * 50 + "\n")
