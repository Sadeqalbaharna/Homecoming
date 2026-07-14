#!/usr/bin/env python3
"""
Firebase Command Listener for Pi
Listens for commands from mobile app and executes them on Pi
"""

import os
import json
import time
import logging
import firebase_admin
from firebase_admin import credentials, db
from voice_enabled_home_automation import VoiceEnabledHomeAutomation

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class FirebaseCommandListener:
    def __init__(self):
        self.home_automation = VoiceEnabledHomeAutomation()
        self.persona_id = "kai_persona_1"  # Default persona ID
        self.init_firebase()
        
    def init_firebase(self):
        """Initialize Firebase connection"""
        try:
            # Use service account key or default credentials
            if not firebase_admin._apps:
                # Try to use service account key if available
                key_path = "/home/pi/.firebase/homecoming-service-account.json"
                if os.path.exists(key_path):
                    cred = credentials.Certificate(key_path)
                else:
                    # Use default credentials
                    cred = credentials.ApplicationDefault()
                
                firebase_admin.initialize_app(cred, {
                    'databaseURL': 'https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app'
                })
                
            logger.info("✅ Firebase initialized successfully")
            
        except Exception as e:
            logger.error(f"❌ Firebase initialization failed: {e}")
            raise
    
    def start_listening(self):
        """Start listening for Firebase commands"""
        commands_ref = db.reference(f'home_automation/{self.persona_id}/commands')
        
        def on_command(event):
            if event.data:
                command_id = event.path.split('/')[-1]
                command_data = event.data
                
                logger.info(f"📱 Received command: {command_id} -> {command_data}")
                
                # Process the command
                self.process_command(command_id, command_data)
        
        # Listen for new commands
        commands_ref.listen(on_command)
        logger.info(f"🎧 Listening for commands at: home_automation/{self.persona_id}/commands")
        
        # Keep the script running
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            logger.info("👋 Firebase listener stopped")
    
    def process_command(self, command_id: str, command_data: dict):
        """Process a command and send response"""
        try:
            action = command_data.get('action')
            target = command_data.get('target') 
            device = command_data.get('device', 'unknown')
            
            logger.info(f"🎵 Processing: {action} on {target}")
            
            # Handle different command types
            result = None
            
            if target == 'music' and action == 'play_mood':
                # Handle mood music command
                mood = command_data.get('mood', 'chill')
                result = self.home_automation.handle_mood_command(mood)
                
            elif target == 'music' and action in ['play', 'pause', 'stop']:
                # Handle music playback commands
                if self.home_automation.music_service:
                    if action == 'play':
                        result = {"success": True, "message": "Music started"}
                    elif action == 'pause':
                        result = {"success": True, "message": "Music paused"}
                    elif action == 'stop':
                        result = {"success": True, "message": "Music stopped"}
                        
            elif target == 'lights':
                # Handle light commands
                result = self.home_automation.handle_light_command(command_data)
                
            else:
                result = {"success": False, "error": f"Unknown command: {action} on {target}"}
            
            # Send response back to Firebase
            self.send_response(command_id, result or {"success": True, "message": "Command processed"})
            
        except Exception as e:
            logger.error(f"❌ Command processing failed: {e}")
            self.send_response(command_id, {"success": False, "error": str(e)})
    
    def send_response(self, command_id: str, result: dict):
        """Send command response back to Firebase"""
        try:
            response_ref = db.reference(f'home_automation/{self.persona_id}/responses/{command_id}')
            
            response_data = {
                'success': result.get('success', False),
                'message': result.get('message', ''),
                'error': result.get('error', ''),
                'timestamp': int(time.time() * 1000)
            }
            
            response_ref.set(response_data)
            
            status = "✅" if result.get('success') else "❌"
            logger.info(f"{status} Response sent: {response_data}")
            
        except Exception as e:
            logger.error(f"❌ Failed to send response: {e}")

if __name__ == "__main__":
    listener = FirebaseCommandListener()
    listener.start_listening()