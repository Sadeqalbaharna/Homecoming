#!/usr/bin/env python3
"""
Minimal AudioDriver test - debug Bluetooth audio playback
"""

import asyncio
import sys
import logging
from pathlib import Path

logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

sys.path.insert(0, str(Path(__file__).parent))

from fixtures_v2.core.driver_base import DriverConfig
from fixtures_v2.drivers.audio_driver import AudioDriver


async def test_audio_driver():
    """Test AudioDriver with pirate ship query"""
    
    logger.info("")
    logger.info("=" * 70)
    logger.info("MINIMAL AUDIODRIVER TEST - PIRATE SHIP".center(70))
    logger.info("=" * 70)
    logger.info("")
    
    # Create driver config
    logger.info("Step 1: Creating AudioDriver configuration...")
    config = DriverConfig(
        driver_id="test_audio",
        driver_type="audio",
        params={"bluetooth_sink": "bluez_output.39_3E_58_14_40_4A.1"}
    )
    logger.info(f"  ✅ Config created")
    logger.info(f"     Sink: {config.params['bluetooth_sink']}")
    
    # Create driver
    logger.info("")
    logger.info("Step 2: Creating AudioDriver instance...")
    driver = AudioDriver(config)
    logger.info(f"  ✅ Driver created")
    
    # Initialize
    logger.info("")
    logger.info("Step 3: Initializing driver (checking mpv)...")
    init_ok = await driver.initialize()
    if not init_ok:
        logger.error("  ❌ Initialization failed!")
        return
    logger.info(f"  ✅ Driver initialized")
    
    # Activate
    logger.info("")
    logger.info("Step 4: Activating audio playback...")
    logger.info(f"  Query: pirate ship sea shanty D&D ambiance music")
    logger.info(f"  Volume: 0.2 (20%)")
    
    success = await driver.activate({
        "query": "pirate ship sea shanty D&D ambiance music",
        "volume": 0.2
    })
    
    if not success:
        logger.error("  ❌ Activation failed!")
        return
    
    logger.info(f"  ✅ Audio activated")
    
    # Wait for audio to play
    logger.info("")
    logger.info("Step 5: Waiting for audio (30 seconds)...")
    logger.info("  Listen to your Bluetooth speaker now! 🎵")
    
    for i in range(30):
        await asyncio.sleep(1)
        if i % 5 == 0:
            logger.info(f"  [{i}s] Still playing...")
    
    # Deactivate
    logger.info("")
    logger.info("Step 6: Stopping audio...")
    await driver.deactivate()
    logger.info(f"  ✅ Audio stopped")
    
    logger.info("")
    logger.info("=" * 70)
    logger.info("TEST COMPLETE".center(70))
    logger.info("=" * 70)


if __name__ == "__main__":
    asyncio.run(test_audio_driver())
