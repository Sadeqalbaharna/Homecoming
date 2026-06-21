#!/usr/bin/env python3
"""
Simple Voice-to-Firebase Music Integration
A minimal example showing how to add "relaxing music" voice commands to Kai
"""

import requests
import time
import random
import logging

def send_relaxing_music_to_firebase():
    """
    Simple function to send relaxing music command to Firebase
    This matches exactly what your mobile app does with HomeAutomationService.sendCommand()
    """
    
    # Firebase config (same as mobile app and listener)
    firebase_url = "https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app"
    persona_id = "kai_persona_1"
    device_id = "raspberry_pi_home"
    
    try:
        # Create command (matches mobile app structure)
        command_id = f"voice_{int(time.time() * 1000)}"
        command_data = {
            "device": device_id,
            "action": "play_mood",
            "target": "music", 
            "mood": "relaxing",
            "shuffle": False,  # Use specific track for relaxing
            "timestamp": int(time.time() * 1000)
        }
        
        # Send to Firebase
        url = f"{firebase_url}/home_automation/{persona_id}/commands/{command_id}.json"
        
        print(f"📤 Sending relaxing music command...")
        print(f"🎵 Command: {command_data}")
        
        response = requests.put(url, json=command_data, timeout=10)
        
        if response.status_code == 200:
            print(f"✅ Command sent successfully! ID: {command_id}")
            
            # Relaxing music responses
            responses = [
                "Playing your relaxing track now. Time to unwind!",
                "I've started track 1 - your peaceful nature sounds.",
                "Relaxing music activated. Let the stress melt away.",
                "Perfect! Your calming music should begin playing shortly."
            ]
            
            confirmation = random.choice(responses)
            print(f"🗣️ Kai would say: '{confirmation}'")
            
            return {
                'success': True,
                'message': 'Relaxing music command sent',
                'kai_response': confirmation
            }
        else:
            print(f"❌ Failed to send command: {response.status_code}")
            return {'success': False, 'message': f'HTTP {response.status_code}'}
            
    except Exception as e:
        print(f"❌ Error: {e}")
        return {'success': False, 'message': str(e)}

def simple_voice_command_handler(voice_input):
    """
    Simple function to check if voice input is a relaxing music request
    This is what you'd add to your existing voice processing
    """
    
    voice_lower = voice_input.lower()
    
    # Check for relaxing music keywords
    relaxing_words = ['relaxing', 'relax', 'calm', 'peaceful', 'soothing']
    music_words = ['music', 'track', 'play', 'song', 'sounds', 'audio']
    
    has_relaxing = any(word in voice_lower for word in relaxing_words)
    has_music = any(word in voice_lower for word in music_words)
    
    if has_relaxing and has_music:
        print(f"🎵 Detected relaxing music request: '{voice_input}'")
        return send_relaxing_music_to_firebase()
    else:
        print(f"ℹ️ Not a relaxing music command: '{voice_input}'")
        return {'success': False, 'message': 'Not a relaxing music command'}

def integration_example():
    """
    Show how this integrates with your existing VoiceEnabledHomeAutomation class
    """
    
    print("🔗 INTEGRATION EXAMPLE")
    print("=" * 30)
    print()
    print("In your existing voice_enabled_home_automation.py file,")
    print("modify the handle_voice_command method like this:")
    print()
    print("```python")
    print("def handle_voice_command(self, command_text: str) -> Dict[str, Any]:")
    print("    \"\"\"Process natural language voice commands\"\"\"")
    print("    ")
    print("    command_lower = command_text.lower()")
    print("    ")
    print("    # NEW: Check for relaxing music first")
    print("    relaxing_words = ['relaxing', 'relax', 'calm', 'peaceful']")
    print("    music_words = ['music', 'track', 'play', 'song', 'sounds']")
    print("    ")
    print("    has_relaxing = any(word in command_lower for word in relaxing_words)")
    print("    has_music = any(word in command_lower for word in music_words)")
    print("    ")
    print("    if has_relaxing and has_music:")
    print("        # Send Firebase command for relaxing music")
    print("        return self._send_relaxing_music_firebase()")
    print("    ")
    print("    # Continue with existing logic for other commands...")
    print("    if any(word in command_lower for word in ['light', 'lights']):")
    print("        # existing light handling")
    print("    # ... rest of your existing code")
    print("```")
    print()
    print("Then add this new method to your class:")
    print()
    print("```python")
    print("def _send_relaxing_music_firebase(self):")
    print("    # Copy the send_relaxing_music_to_firebase() function here")
    print("    # and use self._speak_response() for TTS")
    print("```")

def main():
    """Test the simple integration"""
    
    print("🎤 Simple Voice-to-Firebase Music Integration Test")
    print("=" * 55)
    
    # Test voice inputs
    test_inputs = [
        "Play some relaxing music",           # Should trigger Firebase
        "I want relaxing sounds",             # Should trigger Firebase
        "Can you play track 1 for relaxing?", # Should trigger Firebase
        "Start some peaceful music please",   # Should trigger Firebase
        "Turn on the lights",                 # Should NOT trigger Firebase
        "What time is it?",                   # Should NOT trigger Firebase
        "Play energetic music"                # Should NOT trigger Firebase (not relaxing)
    ]
    
    for voice_input in test_inputs:
        print(f"\n👤 Voice input: \"{voice_input}\"")
        
        result = simple_voice_command_handler(voice_input)
        
        print(f"✅ Success: {result['success']}")
        print(f"📝 Message: {result['message']}")
        
        if result.get('kai_response'):
            print(f"🤖 Kai responds: \"{result['kai_response']}\"")
        
        time.sleep(1)
    
    print("\n" + "=" * 55)
    integration_example()

if __name__ == "__main__":
    main()