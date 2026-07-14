#!/usr/bin/env python3
"""
Enhanced Home Automation Service with Bluetooth Audio Integration
Combines LED control with voice responses via Bluetooth
"""

import json
import time
import logging
from pathlib import Path
from typing import Dict, Any, Optional

# Import our services
try:
    from ws2812b_service import WS2812BService
    from bluetooth_audio_manager import BluetoothAudioManager
    from music_player_service import MusicPlayerService
except ImportError as e:
    print(f"Warning: Could not import services: {e}")
    WS2812BService = None
    BluetoothAudioManager = None
    MusicPlayerService = None

class VoiceEnabledHomeAutomation:
    def __init__(self):
        self.logger = self._setup_logging()
        
        # Initialize services
        self.led_service = WS2812BService() if WS2812BService else None
        self.audio_service = BluetoothAudioManager() if BluetoothAudioManager else None
        self.music_service = MusicPlayerService() if MusicPlayerService else None
        
        # Voice responses for different actions
        self.responses = {
            'light_on': [
                "Turning on the lights for you.",
                "Let there be light! The LEDs are now active.",
                "I've illuminated the room with your LED strip."
            ],
            'light_off': [
                "Turning off all lights. Sweet dreams!",
                "The lights are now off. Energy saved!",
                "Darkness mode activated. All LEDs are off."
            ],
            'color_change': [
                "I've changed the lighting color as requested.",
                "New color activated! The ambiance is perfect.",
                "Color transformation complete!"
            ],
            'effect_rainbow': [
                "Rainbow mode activated! Enjoy the beautiful colors.",
                "Creating a rainbow wave across your LED strip.",
                "Rainbow effect is now flowing through the lights."
            ],
            'effect_breathing': [
                "Breathing effect activated. Very relaxing!",
                "I've set a gentle breathing pattern for the lights.",
                "The lights are now breathing softly."
            ],
            'effect_strobe': [
                "Party mode activated! Let's get this party started!",
                "Strobe lights are flashing! Time to dance!",
                "High energy strobe effect is now active!"
            ],
            'mood_relaxing': [
                "Setting relaxing mood. Dimming lights to a warm glow.",
                "Relaxation mode activated. Perfect for unwinding.",
                "I've created a calm, peaceful lighting atmosphere."
            ],
            'mood_energetic': [
                "Energetic mode! Bright, vibrant colors to keep you motivated.",
                "High energy lighting activated! Let's get things done!",
                "Boosting the energy with dynamic, bright lighting."
            ],
            'mood_romantic': [
                "Romantic mood set. Soft, warm lighting for a perfect ambiance.",
                "Creating a romantic atmosphere with gentle, warm colors.",
                "Love is in the air! Romantic lighting activated."
            ],
            'music_playing': [
                "Now playing your music! Enjoy the tunes.",
                "Music started! Let the melodies flow through your space.",
                "Your soundtrack is now active. Perfect vibes incoming!"
            ],
            'music_stopped': [
                "Music stopped. Silence restored.",
                "Playback ended. Hope you enjoyed the music!",
                "Music paused. Ready for your next request."
            ],
            'playlist_started': [
                "Playlist activated! Multiple songs queued for your enjoyment.",
                "Starting your curated playlist. Sit back and enjoy!",
                "Playlist mode engaged. Great music selection coming up!"
            ],
            'error': [
                "Sorry, I encountered an issue with the lighting system.",
                "There was a problem controlling the LEDs. Please try again.",
                "Oops! Something went wrong with the light control."
            ],
            'success': [
                "Command executed successfully!",
                "All done! Your smart home is responding perfectly.",
                "Mission accomplished! The system is working great."
            ]
        }
        
    def _setup_logging(self):
        """Setup logging"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        return logging.getLogger('VoiceHomeAutomation')
    
    def _get_response(self, category: str) -> str:
        """Get a random response from a category"""
        import random
        responses = self.responses.get(category, self.responses['success'])
        return random.choice(responses)
    
    def _speak_response(self, response: str):
        """Speak a response via Bluetooth audio"""
        if self.audio_service:
            try:
                self.audio_service.play_text_to_speech(response)
                self.logger.info(f"Spoke: {response}")
            except Exception as e:
                self.logger.error(f"Failed to speak response: {e}")
        else:
            self.logger.info(f"Would speak: {response}")
    
    def handle_light_command(self, command: Dict[str, Any]) -> Dict[str, Any]:
        """Handle lighting command with voice response"""
        
        try:
            action = command.get('action', 'unknown')
            
            # Execute LED command
            if self.led_service:
                result = self.led_service.update_leds(command)
                if not result.get('success', False):
                    response = self._get_response('error')
                    self._speak_response(response)
                    return {'success': False, 'message': response}
            
            # Generate appropriate voice response
            if action == 'turn_on':
                response = self._get_response('light_on')
            elif action == 'turn_off':
                response = self._get_response('light_off')
            elif action == 'set_color':
                response = self._get_response('color_change')
            elif command.get('effect') == 'rainbow':
                response = self._get_response('effect_rainbow')
            elif command.get('effect') == 'breathing':
                response = self._get_response('effect_breathing')
            elif command.get('effect') == 'strobe':
                response = self._get_response('effect_strobe')
            else:
                response = self._get_response('success')
            
            # Speak the response
            self._speak_response(response)
            
            return {
                'success': True,
                'message': response,
                'command_executed': command
            }
            
        except Exception as e:
            error_response = self._get_response('error')
            self._speak_response(error_response)
            self.logger.error(f"Light command error: {e}")
            return {'success': False, 'message': str(e)}
    
    def handle_mood_command(self, mood: str) -> Dict[str, Any]:
        """Handle mood setting with appropriate lighting and voice"""
        
        mood_configs = {
            'relaxing': {
                'effect': 'breathing',
                'color': [255, 180, 120],  # Warm white
                'brightness': 0.3,
                'speed': 20
            },
            'energetic': {
                'effect': 'rainbow',
                'brightness': 0.8,
                'speed': 60
            },
            'romantic': {
                'effect': 'solid',
                'color': [255, 100, 150],  # Soft pink
                'brightness': 0.2
            },
            'party': {
                'effect': 'strobe',
                'colors': [[255, 0, 0], [0, 255, 0], [0, 0, 255]],
                'brightness': 1.0,
                'speed': 80
            },
            'focus': {
                'effect': 'solid',
                'color': [255, 255, 255],  # Bright white
                'brightness': 0.6
            }
        }
        
        config = mood_configs.get(mood.lower())
        if not config:
            response = f"I don't recognize the mood '{mood}'. Try relaxing, energetic, romantic, party, or focus."
            self._speak_response(response)
            return {'success': False, 'message': response}
        
        # Execute the mood lighting
        result = self.handle_light_command(config)
        
        if result['success']:
            mood_response = self._get_response(f'mood_{mood.lower()}')
            if mood_response != result['message']:  # Don't double-speak
                self._speak_response(mood_response)
            
            return {
                'success': True,
                'message': f"{mood.title()} mood activated!",
                'mood': mood,
                'config': config
            }
        
        return result
    
    def handle_voice_command(self, command_text: str) -> Dict[str, Any]:
        """Process natural language voice commands"""
        
        command_lower = command_text.lower()
        
        # Light control commands
        if any(word in command_lower for word in ['light', 'lights', 'led', 'strip']):
            if any(word in command_lower for word in ['on', 'turn on', 'activate']):
                return self.handle_light_command({'action': 'turn_on', 'effect': 'solid', 'color': [255, 255, 255]})
            elif any(word in command_lower for word in ['off', 'turn off', 'deactivate']):
                return self.handle_light_command({'action': 'turn_off', 'effect': 'off'})
            elif 'rainbow' in command_lower:
                return self.handle_light_command({'effect': 'rainbow', 'speed': 50})
            elif any(word in command_lower for word in ['red', 'blue', 'green', 'purple']):
                colors = {
                    'red': [255, 0, 0],
                    'blue': [0, 0, 255],
                    'green': [0, 255, 0],
                    'purple': [255, 0, 255],
                    'yellow': [255, 255, 0],
                    'cyan': [0, 255, 255],
                    'white': [255, 255, 255]
                }
                for color_name, color_value in colors.items():
                    if color_name in command_lower:
                        return self.handle_light_command({'effect': 'solid', 'color': color_value})
        
        # Mood commands
        elif any(word in command_lower for word in ['mood', 'atmosphere', 'ambiance']):
            moods = ['relaxing', 'energetic', 'romantic', 'party', 'focus']
            for mood in moods:
                if mood in command_lower:
                    return self.handle_mood_command(mood)
        
        # Time command
        elif any(word in command_lower for word in ['time', 'what time']):
            current_time = time.strftime("%I:%M %p on %A, %B %d")
            response = f"The current time is {current_time}."
            self._speak_response(response)
            return {'success': True, 'message': response}
        
        # Weather command (placeholder)
        elif 'weather' in command_lower:
            response = "I don't have access to weather data yet, but I can tell you it's always sunny in the digital world!"
            self._speak_response(response)
            return {'success': True, 'message': response}
        
        # Music commands
        elif any(word in command_lower for word in ['music', 'song', 'play', 'playlist']):
            if self.music_service:
                result = self.music_service.handle_voice_command(command_text)
                if result['success']:
                    # Don't double-speak if music service already announced
                    if 'Now playing' not in result.get('message', ''):
                        if 'playlist' in result.get('message', '').lower():
                            response = self._get_response('playlist_started')
                        elif 'stopped' in result.get('message', '').lower():
                            response = self._get_response('music_stopped')
                        else:
                            response = self._get_response('music_playing')
                        self._speak_response(response)
                return result
            else:
                response = "Sorry, music service is not available right now."
                self._speak_response(response)
                return {'success': False, 'message': response}

        # Joke command
        elif 'joke' in command_lower:
            jokes = [
                "Why did the LED strip go to therapy? It had too many issues with its connections!",
                "What do you call a smart home that tells jokes? A house with a sense of humor!",
                "Why don't robots ever get tired? They have great battery life!",
                "What's a DJ's favorite type of LED? A disco light that never stops spinning!",
                "Why did the Bluetooth speaker break up with the phone? It said the connection was too unstable!"
            ]
            import random
            joke = random.choice(jokes)
            self._speak_response(joke)
            return {'success': True, 'message': joke}
        
        # Default response
        else:
            response = f"I heard '{command_text}'. I can control lights, set moods, play music, tell time and jokes. What would you like me to do?"
            self._speak_response(response)
            return {'success': True, 'message': response}

def main():
    """Test the voice-enabled home automation"""
    
    print("🏠 Voice-Enabled Home Automation Test")
    print("=" * 40)
    
    automation = VoiceEnabledHomeAutomation()
    
    # Test commands
    test_commands = [
        "Turn on the lights",
        "Set rainbow effect",
        "Turn lights to blue",
        "Set mood to relaxing",
        "What time is it?",
        "Tell me a joke",
        "Turn off all lights"
    ]
    
    for command in test_commands:
        print(f"\n🎤 Command: '{command}'")
        result = automation.handle_voice_command(command)
        print(f"✅ Result: {result['message']}")
        time.sleep(3)  # Wait between commands

if __name__ == "__main__":
    main()