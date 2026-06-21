#!/usr/bin/env python3
"""
Firebase Scene Prompt Executor for Raspberry Pi
Listens to Firebase scene_prompts collection and executes scenes
Handles audio playback (YouTube via yt-dlp/mpv), LED lighting, and Bluetooth speaker output
"""

import json
import time
import logging
import subprocess
import sys
import asyncio
import threading
from pathlib import Path
from typing import Dict, Optional
import requests

# Add parent directory to path for fixtures_v2
sys.path.insert(0, str(Path(__file__).parent))

from fixtures_v2.core.driver_base import DriverConfig
from fixtures_v2.drivers.audio_driver import AudioDriver
from fixtures_v2.drivers.led_driver import LEDDriver

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Firebase config
FIREBASE_PROJECT_ID = "homecoming-kai"
FIREBASE_DB_URL = f"https://{FIREBASE_PROJECT_ID}.firebaseio.com"
POLL_INTERVAL_SECONDS = 2


class ScenePromptExecutor:
    """Executes scene prompts from Firebase"""
    
    def __init__(self):
        self.current_scene_id = None
        self.current_process = None
        self.audio_driver = None
        self.led_driver = None
        self.processed_scenes = set()
        
    def load_audio_driver(self):
        """Initialize AudioDriver for YouTube streaming"""
        try:
            audio_config = DriverConfig(
                driver_id="scene_audio",
                driver_type="audio",
                params={"bluetooth_sink": "bluez_output.39_3E_58_14_40_4A.1"}
            )
            self.audio_driver = AudioDriver(audio_config)
            logger.info("✅ AudioDriver initialized")
        except Exception as e:
            logger.error(f"❌ Failed to initialize AudioDriver: {e}")
    
    def load_led_driver(self):
        """Initialize LEDDriver for lighting control"""
        try:
            led_config = DriverConfig(
                driver_id="scene_leds",
                driver_type="led",
                params={"led_count": 300}
            )
            self.led_driver = LEDDriver(led_config)
            logger.info("✅ LEDDriver initialized")
        except Exception as e:
            logger.warning(f"⚠️  LEDDriver unavailable: {e}")
    
    def fetch_pending_scenes(self) -> Optional[Dict]:
        """Fetch scenes from Firebase"""
        try:
            url = f"{FIREBASE_DB_URL}/scene_prompts.json"
            response = requests.get(url, timeout=5)
            
            if response.status_code == 200:
                all_scenes = response.json() or {}
                
                # Find first pending scene we haven't processed yet
                for scene_id, scene_data in all_scenes.items():
                    if (scene_data and 
                        scene_data.get("execution", {}).get("status") == "pending" and
                        scene_id not in self.processed_scenes):
                        scene_data["_id"] = scene_id  # Add ID for tracking
                        return scene_data
            
            return None
        except Exception as e:
            logger.error(f"❌ Firebase fetch error: {e}")
            return None
    
    def update_scene_status(self, scene_id: str, status: str, error: str = None):
        """Update scene execution status in Firebase"""
        try:
            url = f"{FIREBASE_DB_URL}/scene_prompts/{scene_id}/execution.json"
            update = {
                "status": status,
                "started_at": int(time.time()) if status == "executing" else None,
                "completed_at": int(time.time()) if status in ["completed", "error"] else None,
                "error": error
            }
            response = requests.patch(url, json=update, timeout=5)
            logger.info(f"   📍 Firebase status updated: {status}")
            return response.status_code == 200
        except Exception as e:
            logger.error(f"⚠️  Failed to update Firebase: {e}")
            return False
    
    async def execute_lighting(self, scene: Dict):
        """Execute LED lighting animations"""
        if not scene.get("lighting", {}).get("enabled"):
            logger.info("   💡 Lighting disabled for this scene")
            return
        
        if not self.led_driver:
            logger.warning("   ⚠️  LEDDriver not available, skipping lighting")
            return
        
        try:
            lighting = scene["lighting"]
            strip_config = lighting["strips"][0]
            
            logger.info(f"   💡 Setting up lighting: {strip_config['animation']}")
            
            # Convert colors to RGB tuples
            colors = [(c["r"], c["g"], c["b"]) for c in strip_config["colors"]]
            
            # Execute animation
            await self.led_driver.show_animation(
                animation_type=strip_config["animation"],
                colors=colors,
                speed=strip_config.get("speed", 1.0),
                brightness=strip_config.get("brightness", 200),
                loop=True
            )
            
            logger.info(f"   ✅ Lighting animation started")
        except Exception as e:
            logger.error(f"   ❌ Lighting error: {e}")
    
    async def execute_audio(self, scene: Dict):
        """Execute audio playback via Bluetooth speaker"""
        if not scene.get("audio", {}).get("enabled"):
            logger.info("   🔊 Audio disabled for this scene")
            return
        
        if not self.audio_driver:
            logger.error("   ❌ AudioDriver not available, cannot play audio")
            return
        
        try:
            audio = scene["audio"]
            query = audio["query"]
            volume = audio.get("volume_percent", 20) / 100  # Convert to 0-1 scale
            
            logger.info(f"   🔊 Starting audio: '{query}'")
            logger.info(f"      Volume: {audio.get('volume_percent', 20)}% (max 20% for safety)")
            logger.info(f"      Device: {scene['devices']['bluetooth_speaker']['device_name']}")
            
            # Initialize driver first
            if not await self.audio_driver.initialize():
                logger.error("   ❌ AudioDriver initialization failed")
                return
            
            # Play audio via activate method
            success = await self.audio_driver.activate({
                "query": query,
                "volume": volume
            })
            
            if success:
                logger.info(f"   ✅ Audio playback started")
            else:
                logger.error(f"   ❌ Audio playback failed")
        except Exception as e:
            logger.error(f"   ❌ Audio error: {e}")
    
    async def execute_scene(self, scene: Dict):
        """Execute complete scene: lights + audio"""
        scene_id = scene["_id"]
        self.current_scene_id = scene_id
        self.processed_scenes.add(scene_id)
        
        logger.info("")
        logger.info("=" * 70)
        logger.info(f"🎭 EXECUTING SCENE: {scene['scene']['name'].upper()}".center(70))
        logger.info("=" * 70)
        
        # Update Firebase: status = executing
        self.update_scene_status(scene_id, "executing")
        
        try:
            # Execute lighting and audio in parallel
            logger.info(f"   📖 Scene Type: {scene['scene']['type']}")
            logger.info(f"   🎭 Mood: {scene['scene']['mood']}")
            logger.info(f"   📝 {scene['scene']['description']}")
            logger.info("")
            
            # Start both systems
            lighting_task = asyncio.create_task(self.execute_lighting(scene))
            audio_task = asyncio.create_task(self.execute_audio(scene))
            
            # Wait for both to complete (or timeout)
            await asyncio.wait_for(
                asyncio.gather(lighting_task, audio_task),
                timeout=60
            )
            
            # Scene runs for specified duration
            duration = scene["scene"].get("duration_seconds", 300)
            if duration > 0:
                logger.info(f"   ⏱️  Scene running for {duration} seconds...")
                await asyncio.sleep(duration)
            
            # Update Firebase: status = completed
            self.update_scene_status(scene_id, "completed")
            logger.info("")
            logger.info("=" * 70)
            logger.info(f"✅ SCENE COMPLETED".center(70))
            logger.info("=" * 70)
            
        except Exception as e:
            error_msg = str(e)
            logger.error(f"   ❌ Scene execution failed: {error_msg}")
            self.update_scene_status(scene_id, "error", error_msg)
    
    def start_listener(self):
        """Main listener loop"""
        logger.info("")
        logger.info("=" * 70)
        logger.info("🎭 FIREBASE SCENE PROMPT EXECUTOR STARTED".center(70))
        logger.info("=" * 70)
        logger.info("")
        logger.info(f"📍 Listening for scenes in Firebase...")
        logger.info(f"   Project: {FIREBASE_PROJECT_ID}")
        logger.info(f"   Collection: scene_prompts")
        logger.info(f"   Poll interval: {POLL_INTERVAL_SECONDS}s")
        logger.info("")
        
        # Initialize drivers
        self.load_audio_driver()
        self.load_led_driver()
        
        # Main loop
        try:
            while True:
                scene = self.fetch_pending_scenes()
                
                if scene:
                    # Execute in async context
                    asyncio.run(self.execute_scene(scene))
                
                time.sleep(POLL_INTERVAL_SECONDS)
        
        except KeyboardInterrupt:
            logger.info("\n✋ Listener stopped by user")
        except Exception as e:
            logger.error(f"❌ Listener crashed: {e}")


def main():
    """Entry point"""
    executor = ScenePromptExecutor()
    executor.start_listener()


if __name__ == "__main__":
    main()
