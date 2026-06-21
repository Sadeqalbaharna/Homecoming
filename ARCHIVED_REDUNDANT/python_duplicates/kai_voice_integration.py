#!/usr/bin/env python3
"""
Kai Voice Integration - Add to existing VoiceEnabledHomeAutomation
Simple integration that adds intelligent music selection to Kai's voice processing
"""

import logging
from typing import Dict, Any

try:
    from intelligent_kai_music import IntelligentKaiMusicSystem
    from voice_enabled_home_automation import VoiceEnabledHomeAutomation
except ImportError as e:
    print(f"Import warning: {e}")
    IntelligentKaiMusicSystem = None
    VoiceEnabledHomeAutomation = None

class KaiVoiceWithIntelligentMusic:
    """
    Enhanced Kai voice system with intelligent music selection
    Integrates with existing VoiceEnabledHomeAutomation
    """
    
    def __init__(self):
        self.logger = self._setup_logging()
        
        # Initialize intelligent music system
        self.music_system = IntelligentKaiMusicSystem() if IntelligentKaiMusicSystem else None
        
        # Initialize existing voice automation for non-music commands
        self.voice_automation = VoiceEnabledHomeAutomation() if VoiceEnabledHomeAutomation else None
        
        self.logger.info("🤖 Kai Voice with Intelligent Music initialized")
    
    def _setup_logging(self):
        """Setup logging"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        return logging.getLogger('KaiVoiceIntelligent')
    
    def _speak_response(self, response: str):
        """Use existing TTS system to speak response"""
        if self.voice_automation:
            try:
                self.voice_automation._speak_response(response)
                self.logger.info(f"🗣️ Kai spoke: {response}")
            except Exception as e:
                self.logger.error(f"❌ TTS error: {e}")
        else:
            self.logger.info(f"🗣️ Kai would say: {response}")
    
    def handle_voice_command(self, command_text: str) -> Dict[str, Any]:
        """
        Enhanced voice command handler with intelligent music selection
        
        This is the main method that should replace handle_voice_command 
        in your existing voice system
        """
        
        self.logger.info(f"🎤 Kai processing: '{command_text}'")
        
        # First, check if it's a music command using intelligent system
        if self.music_system:
            music_result = self.music_system.handle_kai_voice_command(command_text)
            
            if music_result.get("success", False):
                # It's a music command and was processed successfully
                
                # Speak Kai's intelligent response
                kai_response = music_result.get("kai_response", "Music command processed")
                self._speak_response(kai_response)
                
                # Log the intelligent selection
                self.logger.info(f"🎵 Intelligent selection: Track {music_result['selected_track']} - {music_result['track_name']}")
                self.logger.info(f"🎯 Selection confidence: {music_result['confidence']:.1%}")
                
                return {
                    "success": True,
                    "message": f"Intelligent music selection: {music_result['track_name']}",
                    "command_type": "intelligent_music",
                    "track_selected": music_result["selected_track"],
                    "track_name": music_result["track_name"],
                    "confidence": music_result["confidence"],
                    "kai_response": kai_response,
                    "firebase_sent": True
                }
            
            elif music_result.get("is_music_command") == False:
                # Not a music command, continue to other processing
                pass
            else:
                # Music command but failed to process
                error_response = music_result.get("kai_response", "I'm having trouble with music right now.")
                self._speak_response(error_response)
                
                return {
                    "success": False,
                    "message": "Music command failed",
                    "command_type": "failed_music",
                    "kai_response": error_response
                }
        
        # If not a music command or music system unavailable, use existing automation
        if self.voice_automation:
            self.logger.info("🏠 Processing with existing voice automation")
            
            existing_result = self.voice_automation.handle_voice_command(command_text)
            
            # Add metadata to indicate local processing
            if isinstance(existing_result, dict):
                existing_result["command_type"] = "local_automation"
                existing_result["firebase_sent"] = False
            else:
                # Convert simple response to dict format
                existing_result = {
                    "success": True,
                    "message": str(existing_result),
                    "command_type": "local_automation",
                    "firebase_sent": False
                }
            
            return existing_result
        
        else:
            # No systems available
            fallback_response = f"I heard '{command_text}' but I'm having trouble processing commands right now."
            self._speak_response(fallback_response)
            
            return {
                "success": False,
                "message": "No command processing systems available",
                "command_type": "fallback",
                "kai_response": fallback_response
            }

def integration_example():
    """Show how to integrate this with your existing system"""
    
    print("\n" + "=" * 60)
    print("📖 INTEGRATION INSTRUCTIONS")
    print("=" * 60)
    print()
    print("To add intelligent music selection to your Kai voice system:")
    print()
    print("1. Replace your existing handle_voice_command method:")
    print()
    print("```python")
    print("# In voice_enabled_home_automation.py")
    print("from kai_voice_integration import KaiVoiceWithIntelligentMusic")
    print()
    print("class VoiceEnabledHomeAutomation:")
    print("    def __init__(self):")
    print("        # Your existing initialization")
    print("        ...")
    print("        # Add intelligent music system")
    print("        self.intelligent_kai = KaiVoiceWithIntelligentMusic()")
    print()
    print("    def handle_voice_command(self, command_text: str):")
    print("        # Use intelligent system")
    print("        return self.intelligent_kai.handle_voice_command(command_text)")
    print("```")
    print()
    print("2. Or create a simple wrapper in your main script:")
    print()
    print("```python") 
    print("# In your main voice processing script")
    print("kai_voice = KaiVoiceWithIntelligentMusic()")
    print()
    print("# When you receive voice input:")
    print("def process_voice_input(voice_text):")
    print("    result = kai_voice.handle_voice_command(voice_text)")
    print("    return result")
    print("```")
    print()
    print("🎯 RESULT: Kai will now intelligently analyze voice commands")
    print("   and select the most appropriate track based on context!")

def main():
    """Test the integrated system"""
    
    print("🤖 Kai Intelligent Voice Integration Test")
    print("=" * 50)
    
    # Create integrated system
    kai_voice = KaiVoiceWithIntelligentMusic()
    
    # Test commands that show intelligent selection
    test_scenarios = [
        {
            "scenario": "After work relaxation",
            "commands": [
                "I just got home from work and need to relax",
                "Play something peaceful to help me unwind",
                "I'm feeling stressed, can you calm me down?"
            ]
        },
        {
            "scenario": "Morning motivation", 
            "commands": [
                "I need energy for my morning workout",
                "Play something to pump me up for the day",
                "Motivate me with upbeat music"
            ]
        },
        {
            "scenario": "Focus time",
            "commands": [
                "I need to concentrate on important work",
                "Play focus music for deep thinking",
                "Something to help me study better"
            ]
        },
        {
            "scenario": "Good mood celebration",
            "commands": [
                "I got great news today, play something cheerful!",
                "I'm in an amazing mood, celebrate with me",
                "Play happy music to match my joy"
            ]
        },
        {
            "scenario": "Non-music commands",
            "commands": [
                "What time is it?",
                "Turn on the lights", 
                "Tell me a joke"
            ]
        }
    ]
    
    for scenario_data in test_scenarios:
        scenario = scenario_data["scenario"]
        commands = scenario_data["commands"]
        
        print(f"\n🎭 SCENARIO: {scenario}")
        print("-" * (len(scenario) + 12))
        
        for command in commands:
            print(f"\n👤 User: \"{command}\"")
            
            result = kai_voice.handle_voice_command(command)
            
            print(f"✅ Success: {result.get('success')}")
            print(f"🎵 Type: {result.get('command_type', 'unknown')}")
            
            if result.get('track_selected'):
                print(f"🎯 Selected: Track {result['track_selected']} - {result['track_name']}")
                print(f"📊 Confidence: {result['confidence']:.1%}")
            
            if result.get('kai_response'):
                print(f"🤖 Kai: \"{result['kai_response']}\"")
            else:
                print(f"💬 Message: {result.get('message', 'No message')}")
            
            print(f"🔥 Firebase: {'Yes' if result.get('firebase_sent') else 'No'}")
        
        input("\n⏸️ Press Enter to continue to next scenario...")
    
    integration_example()

if __name__ == "__main__":
    main()