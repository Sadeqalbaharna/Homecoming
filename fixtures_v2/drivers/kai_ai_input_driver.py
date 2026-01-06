"""
Kai AI Input Driver - Receives intelligent ambiance commands from homecoming app
Gets music search prompts and lighting configs from Kai's analysis
"""

import logging
import firebase_admin
from firebase_admin import db
from typing import Dict, Any, Optional
import asyncio

from ..core.driver_base import InputDriver, DriverConfig

logger = logging.getLogger(__name__)


class KaiAIInputDriver(InputDriver):
    """
    Listen to Firebase for ambiance commands from the homecoming app.
    Kai analyzes the user's natural language input and sends:
    - Music mood/search prompt
    - Lighting color/effect/brightness
    - Confidence level
    
    The fixture receives these and routes to appropriate output drivers.
    """
    
    def __init__(self, config: DriverConfig):
        super().__init__(config)
        self.firebase_ref = None
        self.is_listening = False
        self.last_command = None
        self.persona_id = config.params.get('persona_id', 'kai_persona_1')
        self.device_id = config.params.get('device_id', 'raspberry_pi_home')
        self.command_queue: asyncio.Queue = asyncio.Queue()
    
    async def start(self) -> bool:
        """Start listening for Firebase commands"""
        try:
            # Initialize Firebase if not already done
            if not firebase_admin._apps:
                firebase_admin.initialize_app(options={
                    'databaseURL': 'https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app'
                })
            
            self.firebase_ref = db.reference(f'home_automation/{self.persona_id}/commands')
            self.is_listening = True
            
            # Start listening for new commands
            self._listen_for_commands()
            
            self.logger.info(f"🎤 Kai AI input driver started (listening to {self.persona_id})")
            return True
            
        except Exception as e:
            self.logger.error(f"❌ Failed to start Kai AI driver: {e}")
            return False
    
    def _listen_for_commands(self):
        """Set up Firebase listener for ambiance commands"""
        try:
            def on_new_command(message):
                """Called when a new command arrives from Firebase"""
                if message.event == 'put':
                    command_id = message.path.split('/')[-1]
                    command_data = message.data
                    
                    # Skip if this is our own command echo
                    if self.last_command == command_id:
                        return
                    
                    self.logger.info(f"📡 Received command from homecoming app: {command_id}")
                    self.logger.debug(f"Command data: {command_data}")
                    
                    # Queue the command for processing
                    asyncio.create_task(self.command_queue.put({
                        'command_id': command_id,
                        'data': command_data
                    }))
            
            # Start listening
            self.firebase_ref.listen(on_new_command)
            
        except Exception as e:
            self.logger.error(f"❌ Firebase listener error: {e}")
    
    async def stop(self):
        """Stop listening for commands"""
        self.is_listening = False
        self.logger.info("🎤 Kai AI input driver stopped")
    
    async def is_ready(self) -> bool:
        """Check if listening is active"""
        return self.is_listening
    
    async def get_command(self, timeout_ms: int = 5000) -> Optional[Dict[str, Any]]:
        """
        Get next command from Firebase queue.
        
        Returns command like:
        {
            'device': 'raspberry_pi_home',
            'target': 'ambiance',
            'action': 'dnd_ambiance',
            'params': {
                'prompt': 'tavern music',
                'include_music': True,
                'include_smoke': False
            }
        }
        """
        try:
            timeout_s = timeout_ms / 1000.0
            command = await asyncio.wait_for(self.command_queue.get(), timeout=timeout_s)
            self.last_command = command.get('command_id')
            return command.get('data')
        except asyncio.TimeoutError:
            return None
        except Exception as e:
            self.logger.error(f"❌ Error getting command: {e}")
            return None


class KaiCommandInterpreter:
    """
    Interprets Firebase commands from homecoming app and generates fixture outputs.
    
    Examples:
    - 'dnd_ambiance' with prompt='tavern music' -> LED warm colors + tavern music search
    - 'play_mood' with mood='relaxing' -> LED calm colors + relaxation music
    """
    
    @staticmethod
    def interpret_dnd_ambiance(prompt: str, confidence: float = 0.8) -> Dict[str, Any]:
        """
        Interpret D&D ambiance prompt from Kai.
        
        Args:
            prompt: Natural language description (e.g., "tavern music", "spooky dungeon")
            confidence: How confident Kai is about this choice (0-1)
        
        Returns:
            Dictionary with 'music_query' and 'lighting' settings
        """
        
        # D&D scene definitions (from ambiance_service.dart)
        dnd_scenes = {
            'tavern': {
                'music_query': 'medieval tavern music ambience',
                'lighting': {'color': (255, 140, 0), 'effect': 'warm', 'brightness': 200},
                'confidence': 0.9,
            },
            'dungeon': {
                'music_query': 'dark spooky dungeon ambience',
                'lighting': {'color': (100, 50, 150), 'effect': 'pulse', 'brightness': 100},
                'confidence': 0.85,
            },
            'forest': {
                'music_query': 'peaceful forest nature ambient',
                'lighting': {'color': (34, 139, 34), 'effect': 'shimmer', 'brightness': 180},
                'confidence': 0.88,
            },
            'castle': {
                'music_query': 'medieval castle throne room music',
                'lighting': {'color': (200, 150, 100), 'effect': 'steady', 'brightness': 220},
                'confidence': 0.82,
            },
            'battle': {
                'music_query': 'epic battle combat music intense',
                'lighting': {'color': (255, 0, 0), 'effect': 'strobe', 'brightness': 255},
                'confidence': 0.9,
            },
            'spooky': {
                'music_query': 'creepy ghost spooky horror ambience',
                'lighting': {'color': (75, 0, 130), 'effect': 'pulse', 'brightness': 80},
                'confidence': 0.87,
            },
        }
        
        prompt_lower = prompt.lower()
        
        # Try to find matching scene
        for scene_name, scene_config in dnd_scenes.items():
            if scene_name in prompt_lower:
                logger.info(f"✅ D&D Scene detected: {scene_name}")
                return scene_config
        
        # If no exact match, use the prompt directly as music search
        logger.info(f"ℹ️  Using custom prompt: {prompt}")
        return {
            'music_query': prompt,
            'lighting': {'color': (200, 100, 0), 'effect': 'warm', 'brightness': 180},
            'confidence': confidence,
        }
    
    @staticmethod
    def interpret_play_mood(mood: str, confidence: float = 0.8) -> Dict[str, Any]:
        """
        Interpret mood-based music command from Kai.
        
        Args:
            mood: Mood type (relaxing, energetic, focused, happy, ambient)
            confidence: How confident Kai is
        
        Returns:
            Dictionary with music and lighting
        """
        
        mood_configs = {
            'relaxing': {
                'music_query': 'peaceful relaxing ambient music',
                'lighting': {'color': (100, 149, 237), 'effect': 'steady', 'brightness': 150},
                'confidence': 0.9,
            },
            'energetic': {
                'music_query': 'upbeat energetic motivational music',
                'lighting': {'color': (255, 165, 0), 'effect': 'pulse', 'brightness': 255},
                'confidence': 0.85,
            },
            'focused': {
                'music_query': 'concentration focus study lofi music',
                'lighting': {'color': (100, 200, 255), 'effect': 'steady', 'brightness': 200},
                'confidence': 0.88,
            },
            'happy': {
                'music_query': 'happy cheerful uplifting joyful music',
                'lighting': {'color': (255, 215, 0), 'effect': 'shimmer', 'brightness': 240},
                'confidence': 0.9,
            },
            'ambient': {
                'music_query': 'ambient atmospheric background music',
                'lighting': {'color': (128, 128, 128), 'effect': 'steady', 'brightness': 120},
                'confidence': 0.85,
            },
        }
        
        mood_lower = mood.lower()
        
        if mood_lower in mood_configs:
            logger.info(f"✅ Mood detected: {mood}")
            return mood_configs[mood_lower]
        
        # Default to ambient if unknown mood
        logger.warning(f"⚠️  Unknown mood '{mood}', using ambient")
        return mood_configs['ambient']
