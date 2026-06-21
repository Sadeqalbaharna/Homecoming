#!/usr/bin/env python3
"""
Scene Player with Automatic Bluetooth Wake-Up
Wakes Bluetooth speaker BEFORE playing any scene
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
from bluetooth_auto_wake import ensure_bluetooth_ready


async def play_scene_with_bluetooth(scene_file: str):
    """
    Load scene JSON and play audio with automatic Bluetooth wake-up
    
    Args:
        scene_file: Path to scene JSON file
    """
    
    # Load scene
    scene_path = Path(__file__).parent / scene_file
    with open(scene_path, 'r') as f:
        scene = json.load(f)
    
    logger.info("")
    logger.info("=" * 70)
    logger.info(f"🏴‍☠️  SCENE: {scene['scene']['name'].upper()}".center(70))
    logger.info("=" * 70)
    logger.info("")
    
    logger.info(f"📖 Type: {scene['scene']['type']}")
    logger.info(f"🎭 Mood: {scene['scene']['mood']}")
    logger.info(f"📝 {scene['scene']['description']}")
    logger.info("")
    
    # CRITICAL: Wake up Bluetooth FIRST
    logger.info("🔋 STEP 1: BLUETOOTH AUTO-WAKE")
    logger.info("-" * 70)
    
    if not ensure_bluetooth_ready():
        logger.error("❌ Bluetooth wake-up failed!")
        logger.error("   Check that TG-129C speaker is:")
        logger.error("   • Powered ON")
        logger.error("   • In Bluetooth pairing range")
        logger.error("   • Not connected to other devices")
        return False
    
    logger.info("-" * 70)
    logger.info("")
    
    # Now play audio
    logger.info("🔊 STEP 2: STARTING AUDIO PLAYBACK")
    logger.info("-" * 70)
    
    try:
        # Create audio driver
        audio_config = DriverConfig(
            driver_id="scene_audio",
            driver_type="audio",
            params={"bluetooth_sink": scene["devices"]["bluetooth_speaker"]["sink_name"]}
        )
        audio_driver = AudioDriver(audio_config)
        
        # Initialize
        if not await audio_driver.initialize():
            logger.error("❌ AudioDriver initialization failed")
            return False
        
        audio = scene["audio"]
        query = audio["query"]
        volume = audio["volume_percent"] / 100
        
        logger.info(f"🎵 Query: {query}")
        logger.info(f"🔊 Volume: {audio['volume_percent']}% (max 20% for safety)")
        logger.info(f"🎧 Device: {scene['devices']['bluetooth_speaker']['device_name']}")
        logger.info("")
        
        # Activate audio
        success = await audio_driver.activate({
            "query": query,
            "volume": volume
        })
        
        if not success:
            logger.error("❌ Audio activation failed")
            return False
        
        logger.info("✅ Audio playback started")
        logger.info("-" * 70)
        logger.info("")
        
        # Run for scene duration
        duration = scene["scene"].get("duration_seconds", 300)
        logger.info(f"⏱️  Scene running for {duration} seconds...")
        logger.info("   🎵 Enjoy the scene on your Bluetooth speaker!")
        logger.info("")
        
        await asyncio.sleep(duration)
        
        # Cleanup
        await audio_driver.deactivate()
        
        logger.info("")
        logger.info("=" * 70)
        logger.info("✅ SCENE COMPLETE".center(70))
        logger.info("=" * 70)
        
        return True
        
    except Exception as e:
        logger.error(f"❌ Playback error: {e}")
        import traceback
        traceback.print_exc()
        return False


if __name__ == "__main__":
    # Play pirate ship scene
    scene_file = "pirate_ship_scene.json"
    
    if len(sys.argv) > 1:
        scene_file = sys.argv[1]
    
    success = asyncio.run(play_scene_with_bluetooth(scene_file))
    
    sys.exit(0 if success else 1)
