#!/usr/bin/env python3
"""
Firebase Voice Command Bridge
Integrates existing VoiceEnabledHomeAutomation with Firebase command sending
This allows voice commands to trigger Firebase actions like the mobile app
"""

import json
import time
import logging
import requests
import random
from typing import Dict, Any

# Import the existing voice automation
try:
    from voice_enabled_home_automation import VoiceEnabledHomeAutomation
except ImportError:
    print("Warning: Could not import VoiceEnabledHomeAutomation")
    VoiceEnabledHomeAutomation = None

class FirebaseVoiceBridge:
    """Bridge between voice commands and Firebase system"""
    
    def __init__(self):
        self.logger = self._setup_logging()
        
        # Firebase configuration (matches mobile app and listener)
        self.firebase_url = "https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app"
        self.persona_id = "kai_persona_1" 
        self.device_id = "raspberry_pi_home"
        
        # Initialize existing voice automation for non-music commands
        self.voice_automation = VoiceEnabledHomeAutomation() if VoiceEnabledHomeAutomation else None
        
        self.logger.info("🔗 Firebase Voice Bridge initialized")
        self.logger.info(f"🔥 Firebase URL: {self.firebase_url}")
        self.logger.info(f"🎭 Persona ID: {self.persona_id}")
        self.logger.info(f"🏠 Device ID: {self.device_id}")
        
        # Voice responses for Firebase commands
        self.firebase_responses = {
            'relaxing_music': [
                "Starting your relaxing music now. Let the stress melt away.",
                "Playing some peaceful, calming sounds for you.",
                "I've queued up track 1 - your relaxing nature sounds.",
                "Relaxing music activated. Time to unwind and breathe."
            ],
            'command_sent': [
                "Music command sent to the system!",
                "Your request is being processed.",
                "The home automation system received your command."
            ],
            'error': [
                "Sorry, there was an issue sending the command.",
                "I couldn't connect to the music system right now.",
                "Something went wrong with your request."
            ]
        }
    
    def _setup_logging(self):
        """Setup logging"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        return logging.getLogger('FirebaseVoiceBridge')
    
    def _get_response(self, category: str) -> str:
        """Get a random response from a category"""
        responses = self.firebase_responses.get(category, self.firebase_responses['command_sent'])
        return random.choice(responses)
    
    def _speak_response(self, response: str):
        """Speak response using existing voice automation TTS"""
        if self.voice_automation:
            try:
                self.voice_automation._speak_response(response)
                self.logger.info(f"🗣️ Spoke: {response}")
            except Exception as e:
                self.logger.error(f"❌ Failed to speak response: {e}")
        else:
            self.logger.info(f"🗣️ Would speak: {response}")
    
    def send_firebase_music_command(self, action: str, mood: str = "relaxing", **params) -> Dict[str, Any]:
        """
        Send music command to Firebase matching mobile app HomeAutomationService pattern
        """
        try:
            # Generate unique command ID
            command_id = f"voice_{int(time.time() * 1000)}"
            
            # Build command data (matches mobile app structure)
            command_data = {
                "device": self.device_id,
                "action": action,
                "target": "music",
                "mood": mood,
                "timestamp": int(time.time() * 1000),
                **params  # Additional parameters
            }
            
            # Send to Firebase
            url = f"{self.firebase_url}/home_automation/{self.persona_id}/commands/{command_id}.json"
            
            self.logger.info(f"📤 Sending Firebase music command: {action} ({mood})")
            self.logger.info(f"🎵 Command data: {command_data}")
            
            response = requests.put(url, json=command_data, timeout=10)
            
            if response.status_code == 200:
                self.logger.info(f"✅ Firebase command sent successfully: {command_id}")
                
                # Speak specific response for music type
                if mood == "relaxing":
                    music_response = self._get_response('relaxing_music')
                else:
                    music_response = self._get_response('command_sent')
                
                self._speak_response(music_response)
                
                return {
                    'success': True,
                    'command_id': command_id,
                    'message': f"Sent {action} command for {mood} music",
                    'response_spoken': music_response,
                    'firebase_sent': True
                }
            else:
                self.logger.error(f"❌ Firebase command failed: {response.status_code}")
                error_response = self._get_response('error')
                self._speak_response(error_response)
                
                return {
                    'success': False,
                    'message': f"Firebase request failed: {response.status_code}",
                    'response_spoken': error_response,
                    'firebase_sent': False
                }
                
        except Exception as e:
            self.logger.error(f"❌ Error sending Firebase command: {e}")
            error_response = self._get_response('error')
            self._speak_response(error_response)
            
            return {
                'success': False,
                'message': str(e),
                'response_spoken': error_response,
                'firebase_sent': False
            }
    
    def handle_voice_command(self, command_text: str) -> Dict[str, Any]:
        """
        Process voice command - send to Firebase if music, otherwise use existing system
        """
        
        self.logger.info(f"🎤 Processing command: '{command_text}'")
        
        command_lower = command_text.lower()
        
        # Check for relaxing music specifically
        if any(word in command_lower for word in ['relaxing', 'relax', 'calm', 'peaceful']) and \
           any(word in command_lower for word in ['music', 'track', 'play', 'song']):
            
            self.logger.info("🎵 Detected relaxing music request - sending Firebase command")
            
            return self.send_firebase_music_command(
                action="play_mood",
                mood="relaxing",
                shuffle=False  # Use specific relaxing track
            )
        
        # Check for other music commands that could go to Firebase
        elif any(word in command_lower for word in ['music', 'play music', 'start music']):
            
            # Determine mood from command
            if any(word in command_lower for word in ['energetic', 'upbeat', 'pump up']):
                mood = "energetic"
            elif any(word in command_lower for word in ['ambient', 'background', 'nature']):
                mood = "ambient"
            else:
                mood = "relaxing"  # Default to relaxing
            
            self.logger.info(f"🎵 Detected {mood} music request - sending Firebase command")
            
            return self.send_firebase_music_command(
                action="play_mood", 
                mood=mood,
                shuffle=(mood != "relaxing")  # Don't shuffle relaxing music
            )
        
        # Check for stop music
        elif any(word in command_lower for word in ['stop music', 'stop the music', 'turn off music']):
            
            self.logger.info("🛑 Detected stop music request - sending Firebase command")
            
            return self.send_firebase_music_command(
                action="stop_music",
                mood=""
            )
        
        # For all other commands, use existing voice automation system
        else:
            self.logger.info("🏠 Non-music command - using existing voice automation")
            
            if self.voice_automation:
                result = self.voice_automation.handle_voice_command(command_text)
                result['firebase_sent'] = False
                result['source'] = 'local_automation'
                return result
            else:
                response = f"I heard '{command_text}' but the local automation system isn't available."
                self._speak_response(response)
                return {
                    'success': False,
                    'message': response,
                    'firebase_sent': False,
                    'source': 'bridge_only'
                }

def main():
    """Test the Firebase Voice Bridge"""
    
    print("🌉 Firebase Voice Bridge Test")
    print("=" * 40)
    
    bridge = FirebaseVoiceBridge()
    
    # Test commands focusing on relaxing music
    test_commands = [
        "Play relaxing music",  # Should send Firebase command
        "I want to relax with some music",  # Should send Firebase command  
        "Can you play track 1 relaxing music?",  # Should send Firebase command
        "Start some relaxing sounds",  # Should send Firebase command
        "Play energetic music",  # Should send Firebase command
        "Stop the music",  # Should send Firebase command
        "Turn on the lights",  # Should use local automation
        "What time is it?",  # Should use local automation
        "Tell me a joke"  # Should use local automation
    ]
    
    for command in test_commands:
        print(f"\n🎤 Testing: '{command}'")
        
        result = bridge.handle_voice_command(command)
        
        print(f"✅ Success: {result.get('success')}")
        print(f"🔥 Firebase sent: {result.get('firebase_sent', False)}")
        print(f"📝 Source: {result.get('source', 'unknown')}")
        print(f"💬 Message: {result.get('message')}")
        
        if 'response_spoken' in result:
            print(f"🗣️ Spoken: {result['response_spoken']}")
        
        time.sleep(2)  # Brief pause between commands

if __name__ == "__main__":
    main()