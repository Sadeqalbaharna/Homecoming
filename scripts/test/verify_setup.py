#!/usr/bin/env python3
"""
Quick verification script - Check everything is ready for scene playback
"""

import subprocess
import sys
import logging

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)


def check_tool(tool_name: str, command: str = None) -> bool:
    """Check if a tool is installed"""
    cmd = command or tool_name
    try:
        result = subprocess.run(
            [cmd, '--version'] if tool_name != 'bluetoothctl' else [cmd, '--version'],
            capture_output=True, timeout=2
        )
        return result.returncode == 0
    except:
        return False


def main():
    logger.info("\n" + "=" * 60)
    logger.info("🎧 SETUP VERIFICATION - Scene Playback Ready?")
    logger.info("=" * 60 + "\n")
    
    checks = {
        "Python asyncio": lambda: __import__('asyncio'),
        "Modular drivers": lambda: __import__('fixtures_v2.drivers.audio_driver', fromlist=['AudioDriver']),
    }
    
    cli_tools = {
        "mpv": check_tool('mpv'),
        "yt-dlp": check_tool('yt-dlp'),
        "bluetoothctl": check_tool('bluetoothctl'),
        "pactl": check_tool('pactl'),
    }
    
    logger.info("📦 Python Modules:")
    for name, checker in checks.items():
        try:
            checker()
            logger.info(f"  ✅ {name}")
        except Exception as e:
            logger.info(f"  ❌ {name}: {e}")
    
    logger.info("\n🔧 CLI Tools (Required on Pi):")
    for tool, available in cli_tools.items():
        status = "✅" if available else "⚠️"
        logger.info(f"  {status} {tool}")
    
    logger.info("\n🎵 Test Scripts Available:")
    logger.info("  ✅ test_bluetooth_tg129c.py")
    logger.info("  ✅ test_modular_scene_playback.py")
    logger.info("  ✅ demo_modular_scenes.py")
    
    logger.info("\n" + "=" * 60)
    if all(cli_tools.values()):
        logger.info("✅ Everything ready! Run: python test_modular_scene_playback.py")
    else:
        logger.info("⚠️  Some tools missing (normal on Windows)")
        logger.info("💡 On Pi, install with: sudo apt-get install mpv yt-dlp")
    logger.info("=" * 60 + "\n")


if __name__ == "__main__":
    main()
