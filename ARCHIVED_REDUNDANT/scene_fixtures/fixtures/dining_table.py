"""
Dining Table Fixture - Example modular smart fixture
Demonstrates how to build a complete fixture with inputs and outputs
"""

import logging
import asyncio
from typing import List

from ..core.fixture_base import BaseFixture, FixtureConfig, FixtureType, InputEvent, OutputCommand, FixtureState
from ..core.driver_base import DriverConfig
from ..drivers.voice_input_driver import VoiceInputDriver
from ..drivers.led_driver import LEDDriver
from ..drivers.audio_driver import AudioDriver
from ..drivers.kai_ai_input_driver import KaiAIInputDriver, KaiCommandInterpreter

logger = logging.getLogger(__name__)


class DiningTableFixture(BaseFixture):
    """
    Smart Dining Table with:
    - Voice input (Kai AI)
    - LED strip output (mood lighting)
    - Speaker output (background music)
    
    Example: "User says 'tavern music'" ->
    - Table detects D&D scene
    - Activates warm LED lighting (255, 140, 0)
    - Searches YouTube for "tavern music"
    - Starts playback on Bluetooth speaker
    """
    
    async def initialize(self) -> bool:
        """Set up all drivers for the table"""
        try:
            self.logger.info(f"🎭 Initializing {self.config.fixture_type.value} fixture...")
            
            # Create input drivers
            voice_config = DriverConfig(
                driver_id="voice_input",
                driver_type="voice",
                enabled=True,
                params={}
            )
            self.voice_input = VoiceInputDriver(voice_config)
            self.input_drivers["voice_input"] = self.voice_input
            
            await self.voice_input.start()
            
            # Create Kai AI input driver (listens to Firebase for ambiance commands)
            kai_config = DriverConfig(
                driver_id="kai_ai_input",
                driver_type="kai_ai",
                enabled=True,
                params={
                    'persona_id': 'kai_persona_1',
                    'device_id': 'raspberry_pi_home',
                }
            )
            self.kai_input = KaiAIInputDriver(kai_config)
            self.input_drivers["kai_ai_input"] = self.kai_input
            
            try:
                await self.kai_input.start()
                self.logger.info("✅ Kai AI input driver initialized")
            except Exception as e:
                self.logger.warning(f"⚠️ Kai AI input driver failed: {e}")
            
            # Create output drivers
            # LED Strip
            led_config = DriverConfig(
                driver_id="led_main",
                driver_type="led",
                enabled=True,
                params={
                    'gpio_pin': 18,
                    'led_count': 300,
                    'brightness': 200,
                }
            )
            self.led_driver = LEDDriver(led_config)
            self.output_drivers["led_main"] = self.led_driver
            
            led_ready = await self.led_driver.initialize()
            if not led_ready:
                self.logger.warning("⚠️ LED driver failed to initialize")
            
            # Speaker
            audio_config = DriverConfig(
                driver_id="speaker_1",
                driver_type="audio",
                enabled=True,
                params={
                    'sink_name': 'bluez_output.39_3E_58_14_40_4A.1',  # TG-129C Bluetooth
                    'mpv_path': 'mpv',
                    'yt_dlp_path': 'yt-dlp',
                }
            )
            self.audio_driver = AudioDriver(audio_config)
            self.output_drivers["speaker_1"] = self.audio_driver
            
            audio_ready = await self.audio_driver.initialize()
            if not audio_ready:
                self.logger.warning("⚠️ Audio driver failed to initialize")
            
            self.state = FixtureState.READY
            self.logger.info(f"✅ {self.config.fixture_id} ready!")
            return True
            
        except Exception as e:
            self.logger.error(f"❌ Initialization failed: {e}")
            self.state = FixtureState.ERROR
            return False
    
    async def process_input(self, event: InputEvent) -> List[OutputCommand]:
        """
        Process input from any source (voice, Kai AI, etc.) and generate outputs.
        """
        try:
            commands = []
            
            # Handle Kai AI ambiance commands from Firebase
            if event.source == "kai_ai":
                return await self._process_kai_ai_input(event)
            
            # Handle manual voice input
            if event.source != "voice":
                return commands
            
            text = event.data.get("text", "").lower()
            self.logger.info(f"🎯 Processing voice input: {text}")
            
            # Detect D&D scene type and generate appropriate outputs
            scene_info = self._analyze_dnd_scene(text)
            
            if scene_info:
                # Add LED command
                commands.append(OutputCommand(
                    driver_id="led_main",
                    action="activate",
                    params={
                        'color': scene_info['color'],
                        'effect': scene_info['effect'],
                        'brightness': 200,
                    }
                ))
                
                # Add music command
                commands.append(OutputCommand(
                    driver_id="speaker_1",
                    action="activate",
                    params={
                        'query': scene_info['music_query'],
                        'volume': 0.7,
                    }
                ))
                
                self.logger.info(f"✅ Scene detected: {scene_info['scene_name']}")
            else:
                self.logger.warning(f"⚠️ No D&D scene detected in input")
            
            return commands
            
        except Exception as e:
            self.logger.error(f"❌ Error processing input: {e}")
            return []
    
    def _analyze_dnd_scene(self, text: str) -> dict:
        """
        Analyze voice input to detect D&D scenes and generate appropriate outputs.
        This is a simplified version - in production, use the AI music engine.
        """
        
        # Scene definitions: keywords -> (color, effect, music_query)
        scenes = {
            'tavern': {
                'keywords': ['tavern', 'inn', 'bar', 'drink', 'ale', 'mead', 'medieval'],
                'color': (255, 140, 0),  # Orange
                'effect': 'warm',
                'music_query': 'cozy medieval tavern music fantasy',
                'scene_name': 'Tavern'
            },
            'dungeon': {
                'keywords': ['dungeon', 'underground', 'dark', 'trapped', 'prison'],
                'color': (128, 0, 128),  # Purple
                'effect': 'pulse',
                'music_query': 'dark dungeon underground music fantasy',
                'scene_name': 'Dungeon'
            },
            'battle': {
                'keywords': ['battle', 'combat', 'fight', 'attack', 'sword', 'enemy', 'enemy', 'ambush'],
                'color': (220, 20, 60),  # Crimson
                'effect': 'strobe',
                'music_query': 'epic battle music orchestral',
                'scene_name': 'Battle'
            },
            'forest': {
                'keywords': ['forest', 'woods', 'nature', 'walk', 'stroll', 'path'],
                'color': (34, 139, 34),  # Forest green
                'effect': 'shimmer',
                'music_query': 'peaceful forest nature music ambient',
                'scene_name': 'Forest'
            },
            'spooky': {
                'keywords': ['haunted', 'ghost', 'spooky', 'creepy', 'mansion', 'evil'],
                'color': (75, 0, 130),  # Indigo
                'effect': 'flicker',
                'music_query': 'haunted spooky creepy music horror',
                'scene_name': 'Spooky'
            },
            'magic': {
                'keywords': ['magic', 'spell', 'wizard', 'magical', 'enchant', 'mystical'],
                'color': (138, 43, 226),  # Blue Violet
                'effect': 'pulse',
                'music_query': 'mystical magical music fantasy',
                'scene_name': 'Magic'
            },
        }
        
        # Find matching scene
        for scene_key, scene_def in scenes.items():
            if any(keyword in text for keyword in scene_def['keywords']):
                return scene_def
        
        return None
    
    async def _process_kai_ai_input(self, event: InputEvent) -> List[OutputCommand]:
        """
        Process Kai AI ambiance commands from Firebase.
        
        Event data format:
        {
            'prompt': 'tavern music',  # or mood: 'relaxing'
            'confidence': 0.9,
            'lighting_config': {...},  # optional
            'music_query': {...}       # optional
        }
        """
        try:
            commands = []
            data = event.data
            
            # Get the scenario details from Kai's interpretation
            prompt = data.get('prompt', '')
            mood = data.get('mood', '')
            confidence = data.get('confidence', 0.8)
            
            # Interpret the command
            if prompt:
                # D&D ambiance command
                scene_config = KaiCommandInterpreter.interpret_dnd_ambiance(prompt, confidence)
                self.logger.info(f"🎭 Kai AI Scene: {prompt} (confidence: {confidence})")
            elif mood:
                # Mood-based command
                scene_config = KaiCommandInterpreter.interpret_play_mood(mood, confidence)
                self.logger.info(f"😊 Kai AI Mood: {mood} (confidence: {confidence})")
            else:
                self.logger.warning(f"⚠️ No prompt or mood in Kai AI command")
                return commands
            
            # Add LED command
            lighting = scene_config.get('lighting', {})
            if lighting:
                commands.append(OutputCommand(
                    driver_id="led_main",
                    action="activate",
                    params={
                        'color': lighting.get('color', (255, 100, 0)),
                        'effect': lighting.get('effect', 'warm'),
                        'brightness': lighting.get('brightness', 180),
                    }
                ))
                self.logger.info(f"💡 LED: {lighting.get('color')} {lighting.get('effect')}")
            
            # Add music command
            music_query = scene_config.get('music_query', prompt or mood)
            commands.append(OutputCommand(
                driver_id="speaker_1",
                action="activate",
                params={
                    'query': music_query,
                    'volume': 0.2,  # 20% volume for testing
                }
            ))
            self.logger.info(f"🎵 Music: {music_query}")
            
            return commands
            
        except Exception as e:
            self.logger.error(f"❌ Error processing Kai AI input: {e}")
            return []
