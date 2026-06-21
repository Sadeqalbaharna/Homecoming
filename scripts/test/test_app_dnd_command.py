#!/usr/bin/env python3
"""Test D&D ambiance command in the same format as the Flutter app sends via Firebase"""

import firebase_admin
from firebase_admin import credentials, db
import time

# Initialize Firebase (using the same credentials as the listener)
cred = credentials.Certificate("homecoming-5ebf1-firebase-adminsdk-h4nct-3ec38dbc8e.json")
firebase_admin.initialize_app(cred, {
    'databaseURL': 'https://homecoming-5ebf1-default-rtdb.firebaseio.com'
})

# Command data - exactly as the Flutter app would send it
persona_id = "kai_persona_1"
device_id = "raspberry_pi_home"
command_id = f"cmd_{int(time.time() * 1000)}"

command_data = {
    "device": device_id,
    "target": "ambiance",
    "action": "dnd_ambiance",
    "timestamp": int(time.time() * 1000),
    "prompt": "intense thunder storm with lightning strikes",
    "include_music": True,
    "include_smoke": False,
}

print("🎲 Sending D&D Ambiance Command via Firebase")
print("=" * 60)
print(f"📍 Path: home_automation/{persona_id}/commands/{command_id}")
print(f"📦 Command Data:")
for key, value in command_data.items():
    print(f"  {key}: {value}")
print()

# Send command
command_ref = db.reference(f'home_automation/{persona_id}/commands/{command_id}')
command_ref.set(command_data)
print("✅ Command sent to Firebase!")
print()

# Wait for response
print("⏳ Waiting for response from Pi listener...")
response_ref = db.reference(f'home_automation/{persona_id}/responses/{command_id}')

timeout = 30
start_time = time.time()

while time.time() - start_time < timeout:
    response = response_ref.get()
    if response:
        print("📄 Response received:")
        for key, value in response.items():
            print(f"  {key}: {value}")
        print()
        
        if response.get('success'):
            print("🎉 D&D Ambiance activated successfully!")
            print("💡 Check your LEDs for lightning effects")
            print("🎵 Listen for thunder storm music on Bluetooth speaker")
        else:
            print(f"❌ Command failed: {response.get('error', 'Unknown error')}")
        break
    
    time.sleep(0.5)
else:
    print("⏱️ Timeout waiting for response (this is normal for music streaming)")
    print("🎭 Check the Pi listener logs for status")

print()
print("⚡ THUNDER STORM IN PROGRESS ⚡")
