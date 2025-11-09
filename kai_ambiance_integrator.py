"""
Kai Voice to Ambiance Integration
Connects Kai's conversational AI with the Intelligent Ambiance System
Processes voice commands for coordinated music and lighting control
"""

import sys
import os

# Add the current directory to path to import our modules
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.append(current_dir)

from intelligent_ambiance_system import IntelligentAmbianceSystem
import re
import json

class KaiAmbianceIntegrator:
    """Integrates Kai's AI responses with intelligent ambiance control"""
    
    def __init__(self, firebase_url: str = None, persona_id: str = None):
        self.firebase_url = firebase_url or "https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app"
        self.persona_id = persona_id or "kai_persona_1"
        
        # Initialize the ambiance system
        self.ambiance_system = IntelligentAmbianceSystem(
            firebase_url=self.firebase_url,
            persona_id=self.persona_id
        )
        
    def should_kai_handle_ambiance(self, user_message: str) -> bool:
        """
        Determine if Kai should handle this as an ambiance request
        rather than just conversation
        """
        return self.ambiance_system.is_ambiance_request(user_message)
    
    def process_kai_ambiance_request(self, user_message: str) -> dict:
        """
        Process user message through intelligent ambiance system
        Returns both ambiance analysis and suggested Kai response
        """
        # Analyze the ambiance request
        analysis = self.ambiance_system.process_ambiance_request(user_message)
        
        # Generate appropriate Kai response based on analysis
        kai_response = self._generate_kai_response(analysis)
        
        return {
            "ambiance_analysis": analysis,
            "kai_response": kai_response,
            "should_send_commands": analysis.get("commands_sent", False),
            "confidence": analysis.get("confidence", 0)
        }
    
    def _generate_kai_response(self, analysis: dict) -> str:
        """Generate appropriate Kai response based on ambiance analysis"""
        
        profile = analysis.get("selected_profile")
        confidence = analysis.get("confidence", 0)
        description = analysis.get("description", "")
        
        if not profile or confidence < 0.3:
            # Low confidence - ask for clarification
            return ("I'd love to help set the perfect ambiance! Could you be more specific about "
                   "what kind of atmosphere you're looking for? I can create lighting and music "
                   "for themes like forest, ocean, cozy, romantic, party, or focus modes.")
        
        elif confidence < 0.6:
            # Medium confidence - confirm before acting
            return (f"I think you're looking for a {profile.lower()} ambiance - "
                   f"{description.lower()}. Should I set that up for you with coordinated "
                   "lighting and music?")
        
        else:
            # High confidence - act and describe
            track_info = ""
            if analysis.get("music_track"):
                mood = analysis.get("mood", "")
                track_info = f"I'm playing {mood} music (track {analysis['music_track']}) "
            
            lighting_info = ""
            if analysis.get("lighting"):
                lighting = analysis["lighting"]
                color = lighting["color"].replace("_", " ")
                brightness = lighting["brightness"]
                effect = lighting["effect"].replace("_", " ")
                lighting_info = f"and setting {color} lighting at {brightness}% with a {effect} effect. "
            
            return (f"Perfect! I'm creating a {profile.lower()} ambiance for you. "
                   f"{track_info}{lighting_info}"
                   f"{description} How does that feel?")

# Integration functions for use in Kai's AI pipeline
def integrate_with_kai_ai():
    """
    This function should be called in Kai's AI response pipeline
    to check for and handle ambiance requests
    """
    
    # Initialize the integrator (this would be done once in the main app)
    integrator = KaiAmbianceIntegrator()
    
    def process_message_for_ambiance(user_message: str) -> dict:
        """
        Process user message and return ambiance handling info
        Use this in Kai's AI service before generating regular responses
        """
        
        if integrator.should_kai_handle_ambiance(user_message):
            # This is an ambiance request - handle specially
            result = integrator.process_kai_ambiance_request(user_message)
            
            return {
                "is_ambiance_request": True,
                "handle_with_ambiance": True,
                "suggested_response": result["kai_response"],
                "ambiance_commands_sent": result["should_send_commands"],
                "confidence": result["confidence"],
                "analysis": result["ambiance_analysis"]
            }
        else:
            # Regular conversation - let normal AI handle it
            return {
                "is_ambiance_request": False,
                "handle_with_ambiance": False
            }
    
    return process_message_for_ambiance

# Example integration code for Kai's AI service
"""
To integrate this with Kai's AI service, add this to the message processing pipeline:

```dart
// In your Dart AI service, before calling the regular AI:

bool checkForAmbianceRequest(String userMessage) {
  // Call the Python ambiance integrator
  final result = await callPythonAmbianceIntegrator(userMessage);
  
  if (result['is_ambiance_request'] && result['confidence'] > 0.6) {
    // High confidence ambiance request - use suggested response
    return result['suggested_response'];
  } else if (result['is_ambiance_request'] && result['confidence'] > 0.3) {
    // Medium confidence - add to context for AI
    aiContext += "User seems to be requesting ambiance control. ";
  }
  
  // Continue with normal AI processing
  return null; // Let normal AI handle it
}
```
"""

# Test the integration
if __name__ == "__main__":
    print("🎭 Testing Kai Ambiance Integration\n")
    
    integrator = KaiAmbianceIntegrator()
    
    test_messages = [
        "Hey Kai, give me forest ambiance",
        "Create a romantic mood", 
        "I want to focus on work",
        "Set up party lighting",
        "Make it cozy in here",
        "Give me ocean vibes",
        "How are you doing today?",  # Non-ambiance
        "I need some relaxing music",  # Partial ambiance
    ]
    
    for message in test_messages:
        print(f"🎤 User: '{message}'")
        
        if integrator.should_kai_handle_ambiance(message):
            result = integrator.process_kai_ambiance_request(message)
            print(f"🤖 Kai: {result['kai_response']}")
            print(f"🎯 Confidence: {result['confidence']:.1%}")
            print(f"📤 Commands sent: {'✅' if result['should_send_commands'] else '❌'}")
        else:
            print("💬 Regular conversation - normal AI handles this")
        
        print("─" * 60)