#!/usr/bin/env python3
"""
Direct Scene Player - Test pirate ship scene playback without Firebase
Loads scene JSON and plays audio directly on Bluetooth speaker
"""

import json
import asyncio
import sys
import logging
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent))

from fixtures_v2.core.driver_base import DriverConfig
from fixtures_v2.drivers.audio_driver import AudioDriver


async def play_scene_directly():
    """Load scene JSON and play audio directly"""
    
    # Load pirate ship scene
    scene_file = Path(__file__).parent / "pirate_ship_scene.json"
    with open(scene_file, 'r') as f:
        scene = json.load(f)
    
    logger.info("=" * 70)
    logger.info(f"🏴‍☠️  DIRECT SCENE PLAYBACK: {scene['scene']['name']}".center(70))
    logger.info("=" * 70)
    logger.info("")
    
    logger.info(f"📖 Scene Type: {scene['scene']['type']}")
    logger.info(f"🎭 Mood: {scene['scene']['mood']}")
    logger.info(f"📝 {scene['scene']['description']}")
    logger.info("")
    
    # Create audio driver
    try:
        logger.info("🔧 Initializing AudioDriver...")
        audio_config = DriverConfig(
            driver_id="scene_audio",
            driver_type="audio",
            params={"bluetooth_sink": scene["devices"]["bluetooth_speaker"]["sink_name"]}
        )
        audio_driver = AudioDriver(audio_config)
        logger.info("✅ AudioDriver initialized")
    except Exception as e:
        logger.error(f"❌ Failed to initialize AudioDriver: {e}")
        return
    
    # Play audio
    try:
        audio = scene["audio"]
        query = audio["query"]
        volume = audio["volume_percent"] / 100  # Convert percentage to 0-1 scale
        
        logger.info("")
        logger.info("🔊 STARTING AUDIO PLAYBACK")
        logger.info(f"   Query: {query}")
        logger.info(f"   Volume: {audio['volume_percent']}% (max 20% for safety)")
        logger.info(f"   Device: {scene['devices']['bluetooth_speaker']['device_name']}")
        logger.info("")
        
        # Initialize audio driver first
        if not await audio_driver.initialize():
            logger.error("❌ AudioDriver initialization failed")
            return
        
        # Activate audio with scene parameters
        success = await audio_driver.activate({
            "query": query,
            "volume": volume
        })
        
        logger.info("✅ Audio playback started")
        logger.info("")
        logger.info(f"⏱️  Scene running for {scene['scene']['duration_seconds']} seconds...")
        logger.info("   Listen to your Bluetooth speaker for pirate ship music! 🎵")
        
        # Run for specified duration
        await asyncio.sleep(scene["scene"]["duration_seconds"])
        
        logger.info("")
        logger.info("=" * 70)
        logger.info("✅ SCENE COMPLETED".center(70))
        logger.info("=" * 70)
        
    except Exception as e:
        logger.error(f"❌ Playback error: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    asyncio.run(play_scene_directly())
