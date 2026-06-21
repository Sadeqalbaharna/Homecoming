#!/usr/bin/env python3
"""
Test script to play a scene on the Bluetooth speaker through Pi
Makes a request to the Kai Consciousness API to trigger ambiance
"""

import requests
import json
import sys

def play_scene(scene_prompt, pi_ip="192.168.1.207", port=5001):
    """Play a scene with music and lighting on the Pi"""
    
    url = f"http://{pi_ip}:{port}/kai/ambiance"
    
    payload = {
        "prompt": scene_prompt,
        "user_id": "test_user",
        "include_music": True,
        "include_smoke": False
    }
    
    print(f"\n🎭 Attempting to play scene: '{scene_prompt}'")
    print(f"📡 Connecting to: {url}")
    
    try:
        response = requests.post(url, json=payload, timeout=10)
        
        if response.status_code == 200:
            result = response.json()
            print("\n✅ Scene activated!")
            print(f"   Scene: {result.get('scene_name', 'Unknown')}")
            print(f"   Description: {result.get('description', 'Unknown')}")
            print(f"   Lighting: {'✓' if result.get('lighting_applied') else '✗'}")
            print(f"   Music: {'✓' if result.get('music_applied') else '✗'}")
            print(f"   Music Query: {result.get('music_query', 'N/A')}")
            print(f"   Confidence: {result.get('confidence', 0):.0%}")
            return True
        else:
            print(f"\n❌ Error: {response.status_code}")
            print(f"   Response: {response.text}")
            return False
            
    except requests.exceptions.ConnectionError:
        print(f"\n❌ Could not connect to Pi at {pi_ip}:{port}")
        print("   Make sure the Pi is running and accessible")
        return False
    except Exception as e:
        print(f"\n❌ Error: {e}")
        return False

if __name__ == "__main__":
    # Default scenes to test
    test_scenes = [
        "A haunted mansion with spooky atmosphere",
        "A mystical forest with ancient trees",
        "A dark dungeon with torchlight",
        "A cozy tavern with warm lighting"
    ]
    
    # Allow custom scene from command line
    if len(sys.argv) > 1:
        scene = " ".join(sys.argv[1:])
    else:
        # Use first test scene
        scene = test_scenes[0]
    
    # Try to find Pi (default to common IP)
    pi_ip = "192.168.213.5"
    
    success = play_scene(scene, pi_ip=pi_ip)
    sys.exit(0 if success else 1)
