#!/usr/bin/env python3
"""Test thunder storm ambiance - lightning effects + storm music"""

import requests
import json

PI_IP = "192.168.227.5"
PORT = 5001
URL = f"http://{PI_IP}:{PORT}/kai/ambiance"

# Epic thunder storm
payload = {
    "prompt": "intense thunder storm with lightning strikes",
    "user_id": "test_user",
    "include_music": True
}

print("⚡ Testing Epic Thunder Storm Ambiance")
print("=" * 60)
print(f"📍 URL: {URL}")
print(f"📦 Payload: {json.dumps(payload, indent=2)}")
print()

try:
    print("🎭 Sending request...")
    response = requests.post(URL, json=payload, timeout=30)
    
    print(f"✅ Status: {response.status_code}")
    
    if response.status_code == 200:
        data = response.json()
        print(f"📄 Response: {json.dumps(data, indent=2)}")
        print()
        
        # Check what was applied
        if data.get('lighting_applied'):
            print(f"💡 Lighting: ✅ Applied - {data.get('scene_name')}")
        else:
            print("💡 Lighting: ❌ Not applied")
            
        if data.get('music_applied'):
            print(f"🎵 Music: ✅ Playing - '{data.get('music_query')}'")
        else:
            print("🎵 Music: ❌ Not playing")
            
        print()
        print("🎉 Thunder storm is live!")
        print("💡 Check your LEDs for purple/white lightning strobe")
        print("🎵 Listen for dramatic storm sounds on Soundtec-Vibe")
    else:
        print(f"❌ Error: {response.text}")
        
except requests.exceptions.Timeout:
    print("⏱️ Request timed out (this is normal for music streaming)")
except Exception as e:
    print(f"❌ Error: {e}")

print()
print("⚡ THUNDER STORM IN PROGRESS ⚡")
print("Press Ctrl+C to stop")
