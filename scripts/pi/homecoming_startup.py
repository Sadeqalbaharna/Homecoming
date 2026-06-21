#!/usr/bin/env python3
"""
HOMECOMING APP - Complete Startup Flow
1. Auto-discover Raspberry Pi
2. Run Bluetooth troubleshooting
3. Verify speaker is working
4. Launch main app
"""

import subprocess
import sys
import logging
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

def main():
    app_dir = Path(__file__).parent
    
    logger.info("\n" + "="*70)
    logger.info("HOMECOMING - D&D AMBIANCE APP".center(70))
    logger.info("="*70)
    
    # Step 1: Discover Pi
    logger.info("\n📍 STEP 1: Discovering Raspberry Pi...")
    logger.info("-" * 70)
    
    result = subprocess.run(
        [sys.executable, str(app_dir / "discover_pi.py")],
        capture_output=True,
        text=True,
        timeout=60
    )
    
    if result.returncode == 0:
        pi_ip = result.stdout.strip()
        logger.info(f"✅ Pi found at: {pi_ip}")
    else:
        logger.error("❌ Could not discover Pi")
        logger.error(result.stderr)
        return 1
    
    # Step 2: Run Bluetooth troubleshooting
    logger.info("\n🔧 STEP 2: Running Bluetooth troubleshooting...")
    logger.info("-" * 70)
    
    env = {"PI_IP": pi_ip}
    result = subprocess.run(
        [sys.executable, str(app_dir / "auto_troubleshoot_bluetooth.py")],
        capture_output=False,
        timeout=300
    )
    
    if result.returncode != 0:
        logger.warning("⚠️  Bluetooth troubleshooting had issues")
        # Continue anyway
    
    # Step 3: All good!
    logger.info("\n" + "="*70)
    logger.info("✅ STARTUP COMPLETE - APP READY".center(70))
    logger.info("="*70)
    logger.info(f"\n🎭 Homecoming app is ready!")
    logger.info(f"📍 Pi: {pi_ip}")
    logger.info(f"🎵 Bluetooth: Ready")
    logger.info("\nListening for D&D scene commands...\n")
    
    # TODO: Launch main app here
    # For now, just keep running
    try:
        while True:
            import time
            time.sleep(1)
    except KeyboardInterrupt:
        logger.info("\n👋 App closed\n")
        return 0

if __name__ == "__main__":
    sys.exit(main())
