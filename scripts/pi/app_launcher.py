#!/usr/bin/env python3
"""
Homecoming App Launcher
Automatically runs Bluetooth troubleshooting on startup
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
    logger.info("HOMECOMING APP LAUNCHER".center(70))
    logger.info("="*70 + "\n")
    
    # Step 1: Auto-troubleshoot Bluetooth
    logger.info("🔧 Running Bluetooth startup checks...\n")
    
    result = subprocess.run(
        [sys.executable, str(app_dir / "auto_troubleshoot_bluetooth.py")],
        capture_output=False
    )
    
    if result.returncode != 0:
        logger.error("\n⚠️  Bluetooth checks failed - some features may not work")
        logger.warning("Continuing anyway...\n")
    
    # Step 2: Launch main app
    logger.info("\n" + "="*70)
    logger.info("LAUNCHING HOMECOMING APP".center(70))
    logger.info("="*70 + "\n")
    
    # TODO: Launch actual app here
    logger.info("✅ App ready - listening for commands\n")
    
    # Keep app running
    try:
        while True:
            import time
            time.sleep(1)
    except KeyboardInterrupt:
        logger.info("\n👋 App closed\n")
        return 0

if __name__ == "__main__":
    sys.exit(main())
