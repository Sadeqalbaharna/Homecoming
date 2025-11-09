#!/usr/bin/env python3
"""
Kai Voice Command Integration Example
Shows how to integrate Kai's voice processing with the Firebase music system
"""

import time
import logging
from typing import Dict, Any

try:
    from firebase_voice_bridge import FirebaseVoiceBridge
except ImportError:
    print("Warning: Could not import FirebaseVoiceBridge")
    FirebaseVoiceBridge = None

class KaiVoiceCommandIntegration:
    """Integration layer for Kai's voice commands with Firebase music system"""
    
    def __init__(self):
        self.logger = self._setup_logging()
        
        # Initialize Firebase bridge for music commands
        self.firebase_bridge = FirebaseVoiceBridge() if FirebaseVoiceBridge else None
        
        self.logger.info("🤖 Kai Voice Command Integration initialized")
        
        # Kai-specific responses for music commands
        self.kai_responses = {
            'relaxing_music_trigger': [
                "I'd be happy to play some relaxing music for you. Let me start that now.",
                "Of course! I'll get some peaceful music going for you.",
                "Absolutely! Time for some relaxing sounds. Starting that up now.",
                "I understand you want to unwind. Let me play some calming music."
            ],
            'music_acknowledgment': [
                "Music command received! The system should start playing shortly.",
                "Got it! I've sent the music request to your home system.",
                "Perfect! Your relaxing music should begin playing any moment.",
                "Command sent! The music system is processing your request."
            ]
        }
    
    def _setup_logging(self):
        """Setup logging"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        return logging.getLogger('KaiVoiceIntegration')
    
    def process_kai_voice_command(self, user_input: str, context: Dict[str, Any] = None) -> Dict[str, Any]:
        """
        Process voice command from Kai's voice recognition system
        This is the main entry point for voice commands from the mobile app voice system
        """
        
        self.logger.info(f"🎤 Kai received voice input: '{user_input}'")
        
        # Check if this is a music-related command
        if self._is_music_command(user_input):
            return self._handle_music_command(user_input, context)
        else:
            # For non-music commands, could integrate with other systems
            return self._handle_other_command(user_input, context)
    
    def _is_music_command(self, user_input: str) -> bool:
        """Check if the voice command is music-related"""
        
        music_keywords = [
            'music', 'song', 'play', 'relaxing', 'relax', 'calm', 'peaceful',
            'track', 'sounds', 'audio', 'tune', 'melody'
        ]
        
        user_lower = user_input.lower()
        return any(keyword in user_lower for keyword in music_keywords)
    
    def _handle_music_command(self, user_input: str, context: Dict[str, Any] = None) -> Dict[str, Any]:
        """Handle music-related voice commands"""
        
        self.logger.info("🎵 Processing music command via Firebase bridge")
        
        if not self.firebase_bridge:
            return {
                'success': False,
                'message': "Music system not available",
                'kai_response': "I'm sorry, the music system isn't available right now.",
                'action_taken': None
            }
        
        try:
            # Send command through Firebase bridge
            result = self.firebase_bridge.handle_voice_command(user_input)
            
            # Generate Kai-specific response
            kai_response = self._generate_kai_response(user_input, result)
            
            return {
                'success': result.get('success', False),
                'message': result.get('message', ''),
                'kai_response': kai_response,
                'action_taken': 'firebase_music_command',
                'firebase_result': result,
                'command_type': 'music'
            }
            
        except Exception as e:
            self.logger.error(f"❌ Error processing music command: {e}")
            
            return {
                'success': False,
                'message': str(e),
                'kai_response': "I'm having trouble with the music system right now. Please try again in a moment.",
                'action_taken': None,
                'command_type': 'music'
            }
    
    def _handle_other_command(self, user_input: str, context: Dict[str, Any] = None) -> Dict[str, Any]:
        """Handle non-music voice commands"""
        
        self.logger.info("🏠 Processing non-music command")
        
        # This could integrate with other home automation systems
        # For now, just acknowledge the command
        
        return {
            'success': True,
            'message': f"Received command: {user_input}",
            'kai_response': f"I heard you say '{user_input}'. I can help with music commands right now. Try asking me to play relaxing music!",
            'action_taken': 'acknowledged',
            'command_type': 'other'
        }
    
    def _generate_kai_response(self, user_input: str, firebase_result: Dict[str, Any]) -> str:
        """Generate Kai's personalized response to music commands"""
        
        import random
        
        if firebase_result.get('success'):
            # Successful music command
            if 'relaxing' in user_input.lower():
                responses = self.kai_responses['relaxing_music_trigger']
                return random.choice(responses)
            else:
                responses = self.kai_responses['music_acknowledgment']
                return random.choice(responses)
        else:
            # Failed music command
            return "I'm having trouble starting the music right now. Let me try that again for you."

def example_integration():
    """Example of how to integrate this with Kai's voice system"""
    
    print("🤖 Kai Voice Command Integration Example")
    print("=" * 45)
    
    # Initialize the integration
    kai_integration = KaiVoiceCommandIntegration()
    
    # Example voice commands that Kai might receive
    example_commands = [
        "Can you play some relaxing music?",
        "I want to relax with track 1",
        "Play the relaxing sounds please",
        "Start some peaceful music",
        "Turn on relaxing music",
        "Stop the music",
        "What's the weather like?",  # Non-music command
    ]
    
    for command in example_commands:
        print(f"\n👤 User says: \"{command}\"")
        
        # Process through Kai integration
        result = kai_integration.process_kai_voice_command(command)
        
        print(f"🤖 Kai responds: \"{result['kai_response']}\"")
        print(f"✅ Success: {result['success']}")
        print(f"⚡ Action: {result['action_taken']}")
        print(f"🎵 Type: {result['command_type']}")
        
        if result.get('firebase_result'):
            firebase = result['firebase_result']
            print(f"🔥 Firebase sent: {firebase.get('firebase_sent', False)}")
        
        time.sleep(1)

def integration_instructions():
    """Print instructions for integrating with existing Kai voice system"""
    
    print("\n" + "=" * 60)
    print("📋 INTEGRATION INSTRUCTIONS")
    print("=" * 60)
    print()
    print("To integrate this with your existing Kai voice processing:")
    print()
    print("1. In your VoiceEnabledHomeAutomation class, modify handle_voice_command:")
    print()
    print("   # Add at the top of handle_voice_command method:")
    print("   from firebase_voice_bridge import FirebaseVoiceBridge")
    print("   firebase_bridge = FirebaseVoiceBridge()")
    print()
    print("2. For music commands, call the bridge:")
    print()
    print("   if any(word in command_lower for word in ['music', 'relaxing', 'track']):")
    print("       return firebase_bridge.handle_voice_command(command_text)")
    print()
    print("3. Or use the full KaiVoiceCommandIntegration for a complete solution")
    print()
    print("4. The Firebase listener (firebase_rest_listener_debug.py) should already")
    print("   be running to receive and execute the commands")
    print()
    print("🎯 Key Point: This connects your voice commands to the same Firebase")
    print("   system that your mobile app uses, ensuring consistent behavior!")

if __name__ == "__main__":
    example_integration()
    integration_instructions()