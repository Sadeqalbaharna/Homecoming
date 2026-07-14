#!/usr/bin/env python3
"""
Voice Command Test for Homecoming Pi
Tests voice commands from mobile app with Bluetooth audio responses
"""

import json
import time
import logging
from pathlib import Path
from bluetooth_audio_manager import BluetoothAudioManager

def test_voice_commands():
    """Test voice command responses via Bluetooth audio"""
    
    print("🎵 Testing Homecoming Pi Voice Commands with Bluetooth Audio")
    print("=" * 60)
    
    # Initialize audio manager
    audio_manager = BluetoothAudioManager()
    
    # Connect to Bluetooth device
    print("📡 Connecting to Bluetooth audio device...")
    if not audio_manager.connect_audio_device():
        print("❌ Failed to connect to Bluetooth device")
        print("💡 Make sure you've paired a Bluetooth speaker/headphones to this Pi")
        return False
    
    # Test basic audio
    print("🔊 Testing basic audio output...")
    if not audio_manager.play_beep(1000, 0.5):
        print("❌ Basic audio test failed")
        return False
    
    time.sleep(1)
    
    # Test TTS
    print("🗣️ Testing Text-to-Speech...")
    test_responses = [
        "Hello! I'm Kai, your AI assistant on the Homecoming Pi.",
        "Voice commands are working perfectly!",
        "I can now respond through your Bluetooth speaker.",
        "Try asking me something from your mobile app!"
    ]
    
    for i, response in enumerate(test_responses, 1):
        print(f"   {i}. Playing: '{response}'")
        if not audio_manager.play_text_to_speech(response):
            print(f"❌ TTS test {i} failed")
            return False
        time.sleep(3)  # Wait between responses
    
    print("✅ Voice command audio tests completed successfully!")
    return True

def simulate_mobile_commands():
    """Simulate voice commands from mobile app"""
    
    print("\n🤖 Simulating Mobile App Voice Commands")
    print("=" * 50)
    
    audio_manager = BluetoothAudioManager()
    
    # Simulate common voice commands and responses
    commands = [
        {
            "command": "Hey Kai, what time is it?",
            "response": "The current time is 3:45 PM on Thursday, November 7th, 2025."
        },
        {
            "command": "Hey Kai, turn on the living room lights",
            "response": "I've turned on the living room lights for you. The LED strip is now glowing warmly."
        },
        {
            "command": "Hey Kai, set the mood to relaxing",
            "response": "Setting relaxing mood. I'm dimming the lights and playing soft ambient colors."
        },
        {
            "command": "Hey Kai, what's the weather like?",
            "response": "It's currently 72 degrees and sunny outside. Perfect weather for a walk!"
        },
        {
            "command": "Hey Kai, tell me a joke",
            "response": "Why don't scientists trust atoms? Because they make up everything! Ha ha ha!"
        }
    ]
    
    for i, cmd in enumerate(commands, 1):
        print(f"\n📱 Command {i}: {cmd['command']}")
        print(f"🎵 Response: {cmd['response']}")
        
        # Play the response via Bluetooth
        if not audio_manager.play_text_to_speech(cmd['response']):
            print("❌ Failed to play response")
        
        time.sleep(4)  # Wait between commands
    
    print("\n✅ Mobile command simulation completed!")

def test_led_with_audio_feedback():
    """Test LED controls with audio feedback"""
    
    print("\n💡 Testing LED Controls with Audio Feedback")
    print("=" * 50)
    
    audio_manager = BluetoothAudioManager()
    
    # Import LED service if available
    try:
        import sys
        sys.path.append('/home/pi/homecoming_pi')
        from ws2812b_service import WS2812BService
        
        led_service = WS2812BService()
        
        # Test different LED effects with voice feedback
        effects = [
            {
                "name": "Rainbow Wave",
                "command": {"effect": "rainbow", "speed": 50},
                "feedback": "Activating rainbow wave effect on the LED strip."
            },
            {
                "name": "Breathing Blue",
                "command": {"effect": "breathing", "color": [0, 100, 255], "speed": 30},
                "feedback": "Setting breathing blue effect. Very calming!"
            },
            {
                "name": "Party Mode",
                "command": {"effect": "strobe", "colors": [[255, 0, 0], [0, 255, 0], [0, 0, 255]], "speed": 80},
                "feedback": "Party mode activated! Let's dance!"
            },
            {
                "name": "Warm White",
                "command": {"effect": "solid", "color": [255, 180, 120]},
                "feedback": "Setting warm white lighting for a cozy atmosphere."
            }
        ]
        
        for effect in effects:
            print(f"\n💡 Testing: {effect['name']}")
            
            # Announce what we're doing
            audio_manager.play_text_to_speech(effect['feedback'])
            time.sleep(2)
            
            # Apply LED effect
            led_service.update_leds(effect['command'])
            time.sleep(3)
        
        # Turn off LEDs
        print("\n🔌 Turning off LEDs")
        audio_manager.play_text_to_speech("Turning off all lights. Good night!")
        led_service.update_leds({"effect": "off"})
        
    except ImportError:
        print("💡 LED service not available - testing audio feedback only")
        audio_manager.play_text_to_speech("LED service is not available, but audio feedback is working perfectly!")

def interactive_test():
    """Interactive test mode"""
    
    print("\n🎮 Interactive Voice Command Test")
    print("=" * 40)
    print("Type voice commands to test audio responses!")
    print("Commands: 'time', 'lights', 'joke', 'weather', 'quit'")
    
    audio_manager = BluetoothAudioManager()
    
    while True:
        try:
            command = input("\n🎤 Enter command (or 'quit'): ").strip().lower()
            
            if command == 'quit':
                audio_manager.play_text_to_speech("Goodbye! Thanks for testing the Homecoming Pi.")
                break
            
            elif command == 'time':
                response = f"The current time is {time.strftime('%I:%M %p on %A, %B %d')}"
                
            elif command == 'lights':
                response = "I've adjusted the lighting for you. The LED strip is now active."
                
            elif command == 'joke':
                jokes = [
                    "Why did the robot go to therapy? It had too many bugs!",
                    "What do you call a robot that takes the long way around? R2-Detour!",
                    "Why don't robots ever panic? They have good backup systems!"
                ]
                import random
                response = random.choice(jokes)
                
            elif command == 'weather':
                response = "It's a beautiful day! Perfect for testing voice commands on the Pi."
                
            else:
                response = f"I heard you say '{command}'. Voice recognition is working great!"
            
            print(f"🤖 Response: {response}")
            audio_manager.play_text_to_speech(response)
            
        except KeyboardInterrupt:
            print("\n👋 Exiting interactive test...")
            break

def main():
    """Main test runner"""
    
    print("🏠 Homecoming Pi - Voice Command & Bluetooth Audio Test")
    print("=" * 60)
    
    # Run all tests
    tests = [
        ("Basic Audio Test", test_voice_commands),
        ("Mobile Command Simulation", simulate_mobile_commands),
        ("LED + Audio Test", test_led_with_audio_feedback),
    ]
    
    for test_name, test_func in tests:
        print(f"\n🧪 Running: {test_name}")
        try:
            if test_func():
                print(f"✅ {test_name} - PASSED")
            else:
                print(f"❌ {test_name} - FAILED")
        except Exception as e:
            print(f"❌ {test_name} - ERROR: {e}")
        
        time.sleep(2)
    
    # Interactive mode
    interactive_test()

if __name__ == "__main__":
    main()