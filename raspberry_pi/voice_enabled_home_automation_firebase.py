#!/usr/bin/env python3
"""
Enhanced Voice-Enabled Home Automation with Firebase Integration
Combines voice command processing with Firebase command sending to match mobile app pattern
"""

import json
import time
import logging
import requests
import random
from pathlib import Path
from typing import Dict, Any, Optional

# Import our existing services
try:
    from ws2812b_service import WS2812BService
    from bluetooth_audio_manager import BluetoothAudioManager
    from music_player_service import MusicPlayerService
except ImportError as e:
    print(f"Warning: Could not import services: {e}")
    WS2812BService = None
    BluetoothAudioManager = None
    MusicPlayerService = None

class VoiceEnabledHomeAutomationFirebase:
    def __init__(self):
        self.logger = self._setup_logging()
        
        # Firebase configuration (matches mobile app)
        self.firebase_url = "https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app"
        self.persona_id = "kai_persona_1"
        self.device_id = "raspberry_pi_home"
        
        # Initialize services
        self.led_service = WS2812BService() if WS2812BService else None
        self.audio_service = BluetoothAudioManager() if BluetoothAudioManager else None
        self.music_service = MusicPlayerService() if MusicPlayerService else None
        
        self.logger.info(f"🔥 Voice-enabled home automation initialized with Firebase integration")
        self.logger.info(f"📱 Firebase URL: {self.firebase_url}")
        self.logger.info(f"🎭 Persona ID: {self.persona_id}")
        self.logger.info(f"🏠 Device ID: {self.device_id}")
        
        # Voice responses for different actions
        self.responses = {
            'music_relaxing': [
                "Playing relaxing music for you. Time to unwind!",
                "I've started some peaceful, calming music. Perfect for relaxation.",
                "Relaxing music is now playing. Let the stress melt away.",
                "Here's some beautiful, soothing music to help you relax."
            ],
            'music_energetic': [
                "Energetic music activated! Let's get pumped up!",
                "Playing upbeat tunes to boost your energy!",
                "High-energy music is now flowing. Time to get motivated!"
            ],
            'music_ambient': [
                "Ambient music playing. Perfect background atmosphere.",
                "I've started some beautiful ambient sounds for you.",
                "Atmospheric music is now creating the perfect mood."
            ],
            'music_stopped': [
                "Music stopped. Silence restored.",
                "Playback ended. Hope you enjoyed the music!",
                "Music paused. Ready for your next request."
            ],
            'command_sent': [
                "Command sent! The system should respond shortly.",
                "I've sent your request to the home automation system.",
                "Your command is being processed by the smart home hub."
            ],
            'error': [
                "Sorry, I encountered an issue processing your request.",
                "There was a problem with the command. Please try again.",
                "Oops! Something went wrong. Let me try that again."
            ],
            'success': [
                "Command executed successfully!",
                "All done! Your request has been processed.",
                "Perfect! The system responded as expected."
            ],
            # Add other response categories from original
            'light_on': [
                "Turning on the lights for you.",
                "Let there be light! The LEDs are now active.",
                "I've illuminated the room with your LED strip."
            ],
            'light_off': [
                "Turning off all lights. Sweet dreams!",
                "The lights are now off. Energy saved!",
                "Darkness mode activated. All LEDs are off."
            ]
        }
        
    def _setup_logging(self):
        """Setup logging"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        return logging.getLogger('VoiceHomeAutomationFirebase')
    
    def _get_response(self, category: str) -> str:
        """Get a random response from a category"""
        responses = self.responses.get(category, self.responses['success'])
        return random.choice(responses)
    
    def _speak_response(self, response: str):
        """Speak a response via Bluetooth audio"""
        if self.audio_service:
            try:
                self.audio_service.play_text_to_speech(response)
                self.logger.info(f"🗣️ Spoke: {response}")
            except Exception as e:
                self.logger.error(f"❌ Failed to speak response: {e}")
        else:
            self.logger.info(f"🗣️ Would speak: {response}")
    
    def send_firebase_command(self, action: str, target: str = "music", **params) -> Dict[str, Any]:
        """
        Send command to Firebase using the same pattern as mobile app HomeAutomationService.sendCommand()
        
        Matches mobile app structure:
        {
            "device": device_id,
            "action": action,
            "target": target,
            "timestamp": timestamp,
            ...params (mood, shuffle, etc.)
        }
        """
        try:
            # Generate unique command ID
            command_id = f"voice_{int(time.time() * 1000)}"
            
            # Build command data (matches mobile app pattern)
            command_data = {
                "device": self.device_id,
                "action": action,
                "target": target,
                "timestamp": int(time.time() * 1000),
                **params  # Additional parameters like mood, shuffle, etc.
            }
            
            # Send to Firebase (matches mobile app path)
            url = f"{self.firebase_url}/home_automation/{self.persona_id}/commands/{command_id}.json"
            
            self.logger.info(f"📤 Sending Firebase command: {action} -> {command_data}")
            
            response = requests.put(url, json=command_data, timeout=10)
            
            if response.status_code == 200:
                self.logger.info(f"✅ Firebase command sent successfully: {command_id}")
                
                # Speak confirmation
                confirmation = self._get_response('command_sent')
                self._speak_response(confirmation)
                
                return {
                    'success': True,
                    'command_id': command_id,
                    'message': f"Command '{action}' sent to Firebase",
                    'response_spoken': confirmation
                }
            else:
                self.logger.error(f"❌ Firebase command failed: {response.status_code}")
                error_message = f"Firebase request failed with status {response.status_code}"
                error_response = self._get_response('error')
                self._speak_response(error_response)
                
                return {
                    'success': False,
                    'message': error_message,
                    'response_spoken': error_response
                }
                
        except Exception as e:
            self.logger.error(f"❌ Error sending Firebase command: {e}")
            error_response = self._get_response('error')
            self._speak_response(error_response)
            
            return {
                'success': False,
                'message': str(e),
                'response_spoken': error_response
            }
    
    def handle_music_voice_command(self, command_text: str) -> Dict[str, Any]:
        """Handle music-related voice commands by sending Firebase commands"""
        
        command_lower = command_text.lower()
        
        # Check for relaxing music request
        if any(word in command_lower for word in ['relaxing', 'relax', 'calm', 'peaceful', 'soothing']):
            self.logger.info(f"🎵 Detected relaxing music request: '{command_text}'")
            
            # Send Firebase command for relaxing music (matches mobile app pattern)
            result = self.send_firebase_command(
                action="play_mood",
                target="music", 
                mood="relaxing",
                shuffle=False  # Use specific track for relaxing
            )
            
            if result['success']:
                # Additional specific response for relaxing music
                relaxing_response = self._get_response('music_relaxing')
                self._speak_response(relaxing_response)
                result['additional_response'] = relaxing_response
            
            return result
        
        # Check for energetic music
        elif any(word in command_lower for word in ['energetic', 'upbeat', 'pump up', 'motivate', 'energy']):
            self.logger.info(f"🎵 Detected energetic music request: '{command_text}'")
            
            result = self.send_firebase_command(
                action="play_mood",
                target="music",
                mood="energetic", 
                shuffle=True
            )
            
            if result['success']:
                energetic_response = self._get_response('music_energetic')
                self._speak_response(energetic_response)
                result['additional_response'] = energetic_response
            
            return result
        
        # Check for ambient music
        elif any(word in command_lower for word in ['ambient', 'atmosphere', 'background', 'nature']):
            self.logger.info(f"🎵 Detected ambient music request: '{command_text}'")
            
            result = self.send_firebase_command(
                action="play_mood",
                target="music",
                mood="ambient",
                shuffle=False
            )
            
            if result['success']:
                ambient_response = self._get_response('music_ambient')
                self._speak_response(ambient_response)
                result['additional_response'] = ambient_response
            
            return result
        
        # Check for stop music
        elif any(word in command_lower for word in ['stop', 'pause', 'turn off music']):
            self.logger.info(f"🛑 Detected stop music request: '{command_text}'")
            
            result = self.send_firebase_command(
                action="stop_music",
                target="music"
            )
            
            if result['success']:
                stop_response = self._get_response('music_stopped')
                self._speak_response(stop_response)
                result['additional_response'] = stop_response
            
            return result
        
        # Check for general play music command
        elif any(word in command_lower for word in ['play music', 'start music', 'music on']):
            self.logger.info(f"🎵 Detected general music request: '{command_text}'")
            
            # Default to relaxing mood if no specific mood detected
            result = self.send_firebase_command(
                action="play_mood",
                target="music",
                mood="relaxing",
                shuffle=False
            )
            
            if result['success']:
                relaxing_response = self._get_response('music_relaxing')
                self._speak_response(relaxing_response)
                result['additional_response'] = relaxing_response
            
            return result
        
        else:
            # Not a recognized music command
            return {
                'success': False,
                'message': f"Music command not recognized: {command_text}",
                'is_music_command': False
            }
    
    def handle_voice_command(self, command_text: str) -> Dict[str, Any]:
        """
        Process natural language voice commands
        Enhanced version that checks for music commands first and sends Firebase commands
        """
        
        self.logger.info(f"🎤 Processing voice command: '{command_text}'")
        
        command_lower = command_text.lower()
        
        # First check if this is a music command - send Firebase command if so
        if any(word in command_lower for word in ['music', 'song', 'play', 'relaxing', 'relax']):
            music_result = self.handle_music_voice_command(command_text)
            
            if music_result.get('success', False) or music_result.get('is_music_command', True):
                return music_result
        
        # If not a Firebase music command, fall back to local processing
        
        # Light control commands (local)
        if any(word in command_lower for word in ['light', 'lights', 'led', 'strip']):
            if any(word in command_lower for word in ['on', 'turn on', 'activate']):
                if self.led_service:
                    result = self.led_service.update_leds({'action': 'turn_on', 'effect': 'solid', 'color': [255, 255, 255]})
                response = self._get_response('light_on')
                self._speak_response(response)
                return {'success': True, 'message': response, 'type': 'local_light'}
            
            elif any(word in command_lower for word in ['off', 'turn off', 'deactivate']):
                if self.led_service:
                    result = self.led_service.update_leds({'action': 'turn_off', 'effect': 'off'})
                response = self._get_response('light_off')
                self._speak_response(response)
                return {'success': True, 'message': response, 'type': 'local_light'}
        
        # Time command (local)
        elif any(word in command_lower for word in ['time', 'what time']):
            current_time = time.strftime("%I:%M %p on %A, %B %d")
            response = f"The current time is {current_time}."
            self._speak_response(response)
            return {'success': True, 'message': response, 'type': 'time'}
        
        # Weather command (placeholder)
        elif 'weather' in command_lower:
            response = "I don't have access to weather data yet, but I can tell you it's always sunny in the digital world!"
            self._speak_response(response)
            return {'success': True, 'message': response, 'type': 'weather'}
        
        # Joke command (local)
        elif 'joke' in command_lower:
            jokes = [
                "Why did the LED strip go to therapy? It had too many issues with its connections!",
                "What do you call a smart home that tells jokes? A house with a sense of humor!",
                "Why don't robots ever get tired? They have great battery life!",
                "What's a DJ's favorite type of LED? A disco light that never stops spinning!",
                "Why did the Bluetooth speaker break up with the phone? It said the connection was too unstable!"
            ]
            joke = random.choice(jokes)
            self._speak_response(joke)
            return {'success': True, 'message': joke, 'type': 'joke'}
        
        # Default response
        else:
            response = f"I heard '{command_text}'. I can control music through Firebase, lights locally, tell time and jokes. What would you like me to do?"
            self._speak_response(response)
            return {'success': True, 'message': response, 'type': 'default'}

def main():
    """Test the voice-enabled home automation with Firebase"""
    
    print("🏠 Voice-Enabled Home Automation with Firebase Test")
    print("=" * 50)
    
    automation = VoiceEnabledHomeAutomationFirebase()
    
    # Test commands - focus on music commands that will use Firebase
    test_commands = [
        "Play relaxing music",
        "I want some relaxing music",
        "Can you play something relaxing?",
        "Play energetic music", 
        "Stop the music",
        "Turn on the lights",
        "What time is it?",
        "Tell me a joke"
    ]
    
    for command in test_commands:
        print(f"\n🎤 Command: '{command}'")
        result = automation.handle_voice_command(command)
        print(f"✅ Result: {result}")
        print(f"📝 Type: {result.get('type', 'unknown')}")
        
        if result.get('success'):
            print(f"💬 Response: {result['message']}")
            if 'response_spoken' in result:
                print(f"🗣️  Spoken: {result['response_spoken']}")
            if 'additional_response' in result:
                print(f"🎵 Music Response: {result['additional_response']}")
        
        time.sleep(3)  # Wait between commands

if __name__ == "__main__":
    main()