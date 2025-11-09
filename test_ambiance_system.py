#!/usr/bin/env python3
"""
Test script for intelligent ambiance system
Sends various voice commands to Firebase to test coordinated music and lighting
"""

import requests
import json
import time
import random

def send_firebase_command(action, target, data):
    """Send command to Firebase for Pi to process"""
    firebase_url = "https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app"
    persona_id = "kai_persona_1"
    
    command_id = f"test_cmd_{int(time.time() * 1000)}_{random.randint(1000, 9999)}"
    
    command_data = {
        "action": action,
        "target": target,
        "device": "raspberry_pi_home",
        "timestamp": int(time.time() * 1000),
        **data
    }
    
    url = f"{firebase_url}/home_automation/{persona_id}/commands/{command_id}.json"
    
    print(f"🔥 Sending command: {command_id}")
    print(f"📋 Data: {json.dumps(command_data, indent=2)}")
    
    try:
        response = requests.put(url, json=command_data, timeout=10)
        if response.status_code == 200:
            print(f"✅ Command sent successfully")
            return command_id
        else:
            print(f"❌ Failed to send command: {response.status_code}")
            return None
    except Exception as e:
        print(f"❌ Error sending command: {e}")
        return None

def test_forest_ambiance():
    """Test 'give me forest ambiance' command"""
    print("\n🌲 Testing Forest Ambiance...")
    
    # Simulate Kai's voice analysis for "give me forest ambiance"
    voice_analysis = {
        "original_input": "give me forest ambiance",
        "matched_keywords": ["forest", "ambiance"],
        "matched_contexts": ["nature", "environment"],
        "confidence": 0.85,
        "selected_track": 7  # Nature sounds track
    }
    
    ambiance_analysis = {
        "profile": "Forest",
        "description": "Peaceful forest with birds chirping and leaves rustling",
        "confidence": 0.85
    }
    
    lighting_config = {
        "color": "light_green",
        "brightness": 70,
        "effect": "gentle_pulse"
    }
    
    # Send coordinated music command
    music_cmd = send_firebase_command("play_mood", "music", {
        "mood": "forest",
        "shuffle": False,
        "voice_analysis": voice_analysis
    })
    
    time.sleep(1)
    
    # Send coordinated lighting command
    lights_cmd = send_firebase_command("set_ambiance_lighting", "lights", {
        "lighting_config": lighting_config,
        "ambiance_analysis": ambiance_analysis
    })
    
    return music_cmd, lights_cmd

def test_ocean_mood():
    """Test 'create ocean mood' command"""
    print("\n🌊 Testing Ocean Mood...")
    
    voice_analysis = {
        "original_input": "create ocean mood",
        "matched_keywords": ["ocean", "mood", "sea"],
        "matched_contexts": ["water", "relaxation"],
        "confidence": 0.78,
        "selected_track": 1  # Relaxing ocean sounds
    }
    
    ambiance_analysis = {
        "profile": "Ocean",
        "description": "Calming ocean waves with seagulls and gentle breeze",
        "confidence": 0.78
    }
    
    lighting_config = {
        "color": "deep_blue", 
        "brightness": 60,
        "effect": "wave"
    }
    
    # Send coordinated commands
    music_cmd = send_firebase_command("play_mood", "music", {
        "mood": "ocean",
        "shuffle": False,
        "voice_analysis": voice_analysis
    })
    
    time.sleep(1)
    
    lights_cmd = send_firebase_command("set_ambiance_lighting", "lights", {
        "lighting_config": lighting_config,
        "ambiance_analysis": ambiance_analysis
    })
    
    return music_cmd, lights_cmd

def test_romantic_evening():
    """Test romantic ambiance"""
    print("\n💕 Testing Romantic Evening...")
    
    voice_analysis = {
        "original_input": "set romantic mood for dinner",
        "matched_keywords": ["romantic", "dinner"],
        "matched_contexts": ["intimate", "evening"],
        "confidence": 0.92,
        "selected_track": 6  # Classical/elegant music
    }
    
    ambiance_analysis = {
        "profile": "Romantic",
        "description": "Intimate romantic setting with soft classical music",
        "confidence": 0.92
    }
    
    lighting_config = {
        "color": "amber",
        "brightness": 30,
        "effect": "candle_flicker"
    }
    
    music_cmd = send_firebase_command("play_mood", "music", {
        "mood": "romantic",
        "shuffle": False,
        "voice_analysis": voice_analysis
    })
    
    time.sleep(1)
    
    lights_cmd = send_firebase_command("set_ambiance_lighting", "lights", {
        "lighting_config": lighting_config,
        "ambiance_analysis": ambiance_analysis
    })
    
    return music_cmd, lights_cmd

def test_party_mode():
    """Test energetic party ambiance"""
    print("\n🎉 Testing Party Mode...")
    
    voice_analysis = {
        "original_input": "activate party mode",
        "matched_keywords": ["party", "energetic"],
        "matched_contexts": ["celebration", "music"],
        "confidence": 0.88,
        "selected_track": 2  # Upbeat party music
    }
    
    ambiance_analysis = {
        "profile": "Party",
        "description": "High-energy party atmosphere with dynamic lighting",
        "confidence": 0.88
    }
    
    lighting_config = {
        "color": "rainbow",
        "brightness": 90,
        "effect": "color_cycle"
    }
    
    music_cmd = send_firebase_command("play_mood", "music", {
        "mood": "party", 
        "shuffle": False,
        "voice_analysis": voice_analysis
    })
    
    time.sleep(1)
    
    lights_cmd = send_firebase_command("set_ambiance_lighting", "lights", {
        "lighting_config": lighting_config,
        "ambiance_analysis": ambiance_analysis
    })
    
    return music_cmd, lights_cmd

def check_responses(command_ids):
    """Check Firebase for command responses"""
    print(f"\n📋 Checking responses for {len(command_ids)} commands...")
    
    firebase_url = "https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app"
    persona_id = "kai_persona_1"
    
    for cmd_id in command_ids:
        if cmd_id:
            try:
                url = f"{firebase_url}/home_automation/{persona_id}/responses/{cmd_id}.json"
                response = requests.get(url, timeout=5)
                
                if response.status_code == 200 and response.json():
                    data = response.json()
                    status = data.get('status', 'unknown')
                    message = data.get('message', 'No message')
                    
                    if status == 'success':
                        print(f"✅ {cmd_id}: {message}")
                    else:
                        print(f"❌ {cmd_id}: {message}")
                else:
                    print(f"⏳ {cmd_id}: No response yet")
                    
            except Exception as e:
                print(f"❌ Error checking {cmd_id}: {e}")

def main():
    """Run all ambiance tests"""
    print("🎯 Testing Intelligent Ambiance System")
    print("=====================================")
    
    all_command_ids = []
    
    # Test different ambiance profiles
    print("\n🧪 Running ambiance tests...")
    
    # Test 1: Forest Ambiance
    music_id, lights_id = test_forest_ambiance()
    all_command_ids.extend([music_id, lights_id])
    
    # Wait between tests
    time.sleep(3)
    
    # Test 2: Ocean Mood
    music_id, lights_id = test_ocean_mood()
    all_command_ids.extend([music_id, lights_id])
    
    time.sleep(3)
    
    # Test 3: Romantic Evening
    music_id, lights_id = test_romantic_evening()
    all_command_ids.extend([music_id, lights_id])
    
    time.sleep(3)
    
    # Test 4: Party Mode
    music_id, lights_id = test_party_mode()
    all_command_ids.extend([music_id, lights_id])
    
    # Wait for Pi to process commands
    print(f"\n⏳ Waiting 10 seconds for Pi to process {len(all_command_ids)} commands...")
    time.sleep(10)
    
    # Check all responses
    check_responses(all_command_ids)
    
    print("\n🎯 Test Summary:")
    print("- Forest Ambiance: Green lights + nature sounds")
    print("- Ocean Mood: Blue lights + ocean waves")  
    print("- Romantic Evening: Amber lights + classical music")
    print("- Party Mode: Rainbow lights + energetic music")
    
    print(f"\n📊 Monitor Pi logs with:")
    print("ssh pi@192.168.1.100 'tail -f /home/pi/firebase_listener.log'")

if __name__ == "__main__":
    main()