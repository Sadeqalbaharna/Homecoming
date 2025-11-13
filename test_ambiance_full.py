#!/usr/bin/env python3
"""Test full D&D ambiance endpoint with lighting AND music"""

import requests
import json

PI_IP = "192.168.179.5"
PORT = 5001
URL = f"http://{PI_IP}:{PORT}/kai/ambiance"

# Test scenarios with lighting and music
test_scenarios = [
    {
        "prompt": "cast fireball",
        "include_music": True,
        "description": "Epic combat with fireball spell"
    },
    {
        "prompt": "entering a spooky dungeon",
        "include_music": True,
        "description": "Dark dungeon exploration"
    },
    {
        "prompt": "peaceful forest scene",
        "include_music": True,
        "description": "Tranquil forest environment"
    },
    {
        "prompt": "tavern music and warm lighting",
        "include_music": True,
        "description": "Cozy medieval tavern"
    },
    {
        "prompt": "epic battle with dragons",
        "include_music": True,
        "description": "Intense dragon combat"
    }
]

def test_ambiance(scenario):
    """Test a single ambiance scenario"""
    print("\n" + "="*60)
    print(f"Testing: {scenario['description']}")
    print("="*60)
    
    payload = {
        "prompt": scenario["prompt"],
        "user_id": "test_user",
        "include_music": scenario["include_music"]
    }
    
    print(f"🎭 Testing full ambiance endpoint...")
    print(f"📍 URL: {URL}")
    print(f"📦 Payload: {json.dumps(payload, indent=2)}")
    print()
    
    try:
        response = requests.post(URL, json=payload, timeout=30)
        
        print(f"✅ Status: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print(f"📄 Response: {json.dumps(data, indent=2)}")
            
            # Check what was applied
            if data.get('lighting_applied'):
                print("💡 Lighting: ✅ Applied")
            else:
                print("💡 Lighting: ❌ Not applied")
                
            if data.get('music_applied'):
                print(f"🎵 Music: ✅ Playing - '{data.get('music_query')}'")
            else:
                print("🎵 Music: ❌ Not playing")
        else:
            print(f"❌ Error: {response.text}")
            
    except requests.exceptions.Timeout:
        print("⏱️ Request timed out (this is normal for music streaming)")
    except Exception as e:
        print(f"❌ Error: {e}")
    
    print()
    input("Press Enter to continue to next test...")

def main():
    print("🎮 D&D Ambiance Full Test Suite")
    print(f"📡 Target: {URL}")
    print(f"🎯 Testing {len(test_scenarios)} scenarios with lighting + music")
    print()
    input("Press Enter to start testing...")
    
    for scenario in test_scenarios:
        test_ambiance(scenario)
    
    print("\n✅ All tests completed!")
    print("🎵 Check your Pi for music playback")
    print("💡 Check your LEDs for lighting effects")

if __name__ == "__main__":
    main()
