#!/usr/bin/env python3
"""
Test script to play a D&D scene on the Bluetooth speaker using the modular architecture
Uses the fixtures_v2 system with AudioDriver for YouTube streaming
"""

import asyncio
import sys
import logging
from pathlib import Path
import subprocess

# Add parent directory to path
test_dir = Path(__file__).parent
sys.path.insert(0, str(test_dir))

from fixtures_v2.core.driver_base import DriverConfig
from fixtures_v2.drivers.audio_driver import AudioDriver

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


async def play_scene_audio(query: str, bluetooth_sink: str = None):
    """
    Play audio from a scene description via YouTube on Bluetooth speaker.
    
    Args:
        query: YouTube search query (e.g., "ambient dungeon music")
        bluetooth_sink: PulseAudio Bluetooth sink name (optional)
    """
    
    logger.info("🎭 D&D Scene Audio Test - Modular Architecture")
    logger.info("=" * 60)
    logger.info("⚠️  VOLUME: CAPPED AT 20% MAX (Public Safety)")
    logger.info("=" * 60)
    
    # Scene definitions
    scenes = {
        "haunted_mansion": {
            "query": "haunted mansion spooky ambiance music",
            "description": "A chilling haunted mansion with ghostly atmosphere"
        },
        "dungeon": {
            "query": "dark dungeon D&D ambiance music",
            "description": "A dark underground dungeon with torchlight"
        },
        "forest": {
            "query": "ancient forest magical adventure music",
            "description": "A mystical ancient forest full of wonder"
        },
        "tavern": {
            "query": "medieval tavern D&D background music",
            "description": "A cozy tavern with warm candlelight and ale"
        },
        "battle": {
            "query": "epic battle D&D combat music",
            "description": "An intense battle scene with heroic music"
        }
    }
    
    # Parse query
    if query in scenes:
        scene_data = scenes[query]
        logger.info(f"🎭 Scene: {scene_data['description']}")
        search_query = scene_data['query']
    else:
        search_query = query
    
    logger.info(f"🎵 Searching for: '{search_query}'")
    logger.info("=" * 60 + "\n")
    
    # Create audio driver configuration
    audio_config = DriverConfig(
        driver_id="scene_audio",
        driver_type="audio",
        params={
            'sink_name': bluetooth_sink,
            'mpv_path': 'mpv',
            'yt_dlp_path': 'yt-dlp',
        }
    )
    
    # Create driver instance
    audio_driver = AudioDriver(audio_config)
    
    # Initialize
    logger.info("🔧 Initializing audio driver...")
    success = await audio_driver.initialize()
    
    if not success:
        logger.error("❌ Audio driver initialization failed")
        logger.info("💡 Make sure mpv and yt-dlp are installed:")
        logger.info("   sudo apt-get install mpv yt-dlp")
        return False
    
    logger.info("✅ Audio driver initialized\n")
    
    # Activate audio playback
    logger.info("▶️ Starting playback...")
    logger.info("⚠️  VOLUME CAPPED AT 20% MAXIMUM FOR PUBLIC SAFETY\n")
    success = await audio_driver.activate({
        'query': search_query,
        'volume': 0.20,  # 20% max - enforced by AudioDriver, cannot go higher
    })
    
    if success:
        logger.info("✅ Scene audio playing!")
        logger.info("\n🎧 Listening to scene audio...")
        logger.info("   Press Ctrl+C to stop\n")
        
        # Keep playing for a while
        try:
            await asyncio.sleep(300)  # Play for 5 minutes
        except KeyboardInterrupt:
            logger.info("\n⏹️  Stopping playback...")
            await audio_driver.deactivate()
            logger.info("✅ Playback stopped")
        
        return True
    else:
        logger.error("❌ Failed to start audio playback")
        return False


async def list_available_scenes():
    """List all available scenes"""
    logger.info("📋 Available Scenes:")
    logger.info("=" * 60)
    scenes = {
        "haunted_mansion": "A chilling haunted mansion with ghostly atmosphere",
        "dungeon": "A dark underground dungeon with torchlight",
        "forest": "A mystical ancient forest full of wonder",
        "tavern": "A cozy tavern with warm candlelight and ale",
        "battle": "An intense battle scene with heroic music"
    }
    
    for i, (scene_id, description) in enumerate(scenes.items(), 1):
        logger.info(f"{i}. {scene_id:20} - {description}")
    
    logger.info("=" * 60 + "\n")
    logger.info("Usage: python test_modular_scene_playback.py <scene_name>")
    logger.info("       Or: python test_modular_scene_playback.py '<youtube_query>'\n")


async def main():
    """Main entry point"""
    await list_available_scenes()
    
    # Get scene from command line or use default
    if len(sys.argv) > 1:
        scene = " ".join(sys.argv[1:])
    else:
        scene = "haunted_mansion"
        logger.info(f"Using default scene: {scene}\n")
    
    # Optional: specify Bluetooth sink
    # bluetooth_sink = "bluez_output.39_3E_58_14_40_4A.1"  # TG-129C speaker
    # Auto-detect TG-129C Bluetooth sink
    try:
        result = subprocess.run(['pactl', 'list', 'sinks'], 
                              capture_output=True, text=True, timeout=5)
        if result.returncode == 0 and 'bluez_output.39_3E_58_14_40_4A' in result.stdout:
            bluetooth_sink = "bluez_output.39_3E_58_14_40_4A.1"
            logger.info("✅ TG-129C Bluetooth speaker detected and will be used")
        else:
            bluetooth_sink = None
            logger.info("ℹ️  No Bluetooth speaker detected, will use system audio")
    except:
        bluetooth_sink = None
    
    success = await play_scene_audio(scene, bluetooth_sink=bluetooth_sink)
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    asyncio.run(main())
