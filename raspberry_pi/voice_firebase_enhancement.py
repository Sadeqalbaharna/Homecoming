#!/usr/bin/env python3
"""
Voice Command Enhancement for Relaxing Music
Adds Firebase integration to existing VoiceEnabledHomeAutomation class
This patch allows voice commands to trigger the same music system as the mobile app
"""

import requests
import time
import logging
import random

class VoiceCommandFirebaseEnhancement:
    """
    Enhancement class that adds Firebase music command capability
    to the existing VoiceEnabledHomeAutomation system
    """
    
    def __init__(self):
        # Firebase configuration (matches mobile app)
        self.firebase_url = "https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app"
        self.persona_id = "kai_persona_1"
        self.device_id = "raspberry_pi_home"
        
        # Setup logging
        self.logger = logging.getLogger('VoiceFirebaseEnhancement')
        
        # Firebase-specific responses
        self.firebase_responses = {
            'relaxing_music': [
                "Playing your relaxing track now. Time to unwind!",
                "I've started track 1 - your peaceful nature sounds.",
                "Relaxing music activated. Let the stress melt away.",
                "Perfect! Your calming music should begin playing shortly."
            ],
            'firebase_success': [
                "Music command sent successfully!",
                "The system received your request.",
                "Your music should start playing any moment now."
            ],
            'firebase_error': [
                "Sorry, I couldn't connect to the music system.",
                "There was an issue with your music request.",
                "Let me try that music command again."
            ]
        }
    
    def send_relaxing_music_command(self, voice_automation_instance):
        """
        Send Firebase command for relaxing music
        Uses the same pattern as mobile app HomeAutomationService.sendCommand()
        """
        try:
            # Generate unique command ID
            command_id = f"voice_{int(time.time() * 1000)}"
            
            # Build command data (matches mobile app structure)
            command_data = {
                "device": self.device_id,
                "action": "play_mood",
                "target": "music",
                "mood": "relaxing",
                "shuffle": False,  # Use specific relaxing track
                "timestamp": int(time.time() * 1000)
            }
            
            # Send to Firebase
            url = f"{self.firebase_url}/home_automation/{self.persona_id}/commands/{command_id}.json"
            
            self.logger.info(f"📤 Sending relaxing music command to Firebase")
            self.logger.info(f"🎵 Command: {command_data}")
            
            response = requests.put(url, json=command_data, timeout=10)
            
            if response.status_code == 200:
                self.logger.info(f"✅ Firebase command sent: {command_id}")
                
                # Speak confirmation using existing TTS
                responses = self.firebase_responses['relaxing_music']
                confirmation = random.choice(responses)
                voice_automation_instance._speak_response(confirmation)
                
                return {
                    'success': True,
                    'message': f"Relaxing music command sent to Firebase",
                    'command_id': command_id,
                    'firebase_response': confirmation
                }
            else:
                self.logger.error(f"❌ Firebase command failed: {response.status_code}")
                error_response = random.choice(self.firebase_responses['firebase_error'])
                voice_automation_instance._speak_response(error_response)
                
                return {
                    'success': False,
                    'message': f"Firebase request failed: {response.status_code}",
                    'firebase_response': error_response
                }
                
        except Exception as e:
            self.logger.error(f"❌ Error sending Firebase command: {e}")
            error_response = random.choice(self.firebase_responses['firebase_error'])
            voice_automation_instance._speak_response(error_response)
            
            return {
                'success': False,
                'message': str(e),
                'firebase_response': error_response
            }

def enhance_voice_command_method(voice_automation_instance):
    """
    Enhance existing handle_voice_command method to support relaxing music via Firebase
    This function shows how to modify the existing voice automation
    """
    
    # Create enhancement instance
    firebase_enhancement = VoiceCommandFirebaseEnhancement()
    
    def enhanced_handle_voice_command(command_text: str):
        """
        Enhanced version of handle_voice_command that checks for relaxing music first
        """
        
        command_lower = command_text.lower()
        
        # Check for relaxing music request - send to Firebase
        if any(word in command_lower for word in ['relaxing', 'relax', 'calm', 'peaceful']) and \
           any(word in command_lower for word in ['music', 'track', 'play', 'song', 'sounds']):
            
            voice_automation_instance.logger.info("🎵 Relaxing music request detected - using Firebase")
            
            # Send Firebase command for relaxing music
            firebase_result = firebase_enhancement.send_relaxing_music_command(voice_automation_instance)
            
            # Return Firebase result with additional metadata
            return {
                'success': firebase_result['success'],
                'message': firebase_result['message'],
                'firebase_sent': True,
                'firebase_response': firebase_result.get('firebase_response'),
                'command_type': 'relaxing_music_firebase'
            }
        
        # For all other commands, use original implementation
        else:
            # Call original handle_voice_command method
            original_result = voice_automation_instance.handle_voice_command_original(command_text)
            
            # Add metadata to indicate local processing
            if isinstance(original_result, dict):
                original_result['firebase_sent'] = False
                original_result['command_type'] = 'local_automation'
            
            return original_result
    
    # Store original method and replace with enhanced version
    voice_automation_instance.handle_voice_command_original = voice_automation_instance.handle_voice_command
    voice_automation_instance.handle_voice_command = enhanced_handle_voice_command
    
    return voice_automation_instance

def test_enhancement():
    """Test the enhancement with a mock voice automation instance"""
    
    print("🧪 Testing Voice Command Enhancement")
    print("=" * 40)
    
    # Mock voice automation class for testing
    class MockVoiceAutomation:
        def __init__(self):
            self.logger = logging.getLogger('MockVoice')
            self.responses_spoken = []
        
        def _speak_response(self, response):
            self.responses_spoken.append(response)
            print(f"🗣️ [MOCK TTS] {response}")
        
        def handle_voice_command(self, command_text):
            # Original mock implementation
            return {
                'success': True,
                'message': f"Mock processed: {command_text}",
                'source': 'mock_original'
            }
    
    # Create mock instance and enhance it
    mock_voice = MockVoiceAutomation()
    enhanced_voice = enhance_voice_command_method(mock_voice)
    
    # Test commands
    test_commands = [
        "Play some relaxing music",          # Should use Firebase
        "I want relaxing sounds",            # Should use Firebase  
        "Can you play track 1 relaxing?",   # Should use Firebase
        "Turn on the lights",                # Should use original
        "What time is it?"                   # Should use original
    ]
    
    for command in test_commands:
        print(f"\n🎤 Testing: '{command}'")
        
        result = enhanced_voice.handle_voice_command(command)
        
        print(f"✅ Success: {result.get('success')}")
        print(f"🔥 Firebase sent: {result.get('firebase_sent', False)}")
        print(f"📝 Type: {result.get('command_type', 'unknown')}")
        print(f"💬 Message: {result.get('message')}")
        
        if result.get('firebase_response'):
            print(f"🎵 Firebase response: {result['firebase_response']}")

def integration_guide():
    """Print guide for integrating this enhancement"""
    
    print("\n" + "=" * 60)
    print("📖 INTEGRATION GUIDE")
    print("=" * 60)
    print()
    print("To add Firebase relaxing music support to your existing voice system:")
    print()
    print("1. Import this enhancement in your voice_enabled_home_automation.py:")
    print("   from voice_firebase_enhancement import enhance_voice_command_method")
    print()
    print("2. In your main() or initialization code, enhance your instance:")
    print("   automation = VoiceEnabledHomeAutomation()")
    print("   automation = enhance_voice_command_method(automation)")
    print()
    print("3. Make sure your Firebase listener is running:")
    print("   python firebase_rest_listener_debug.py")
    print()
    print("4. Test with voice commands like:")
    print("   - 'Play relaxing music'")
    print("   - 'I want some relaxing sounds'") 
    print("   - 'Can you play track 1 for relaxation?'")
    print()
    print("🎯 Result: Voice commands for relaxing music will now trigger")
    print("   the same Firebase system that your mobile app uses!")
    print()
    print("💡 The enhancement preserves all existing functionality while")
    print("   adding Firebase integration only for relaxing music commands.")

if __name__ == "__main__":
    test_enhancement()
    integration_guide()