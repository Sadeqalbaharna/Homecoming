#!/usr/bin/env python3
"""
Quick Bluetooth Speaker Test
Tests audio driver with TG-129C speaker without needing LEDs
"""

import asyncio
import sys
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

sys.path.insert(0, str(__file__).rsplit('\\', 2)[0])

from fixtures_v2.drivers.audio_driver import AudioDriver
from fixtures_v2.core.driver_base import DriverConfig


async def test_bluetooth_speaker():
    """Test audio playback on Bluetooth speaker"""
    
    print("\n" + "="*80)
    print("BLUETOOTH SPEAKER TEST - TG-129C".center(80))
    print("="*80 + "\n")
    
    # Create audio driver configured for TG-129C
    config = DriverConfig(
        driver_id="speaker_1",
        driver_type="audio",
        enabled=True,
        params={
            'sink_name': 'bluez_output.39_3E_58_14_40_4A.1',  # TG-129C
            'mpv_path': 'mpv',
            'yt_dlp_path': 'yt-dlp',
        }
    )
    
    audio = AudioDriver(config)
    
    # Test 1: Initialize
    print("🎵 TEST 1: Initialize Audio Driver")
    print("-" * 80)
    init_success = await audio.initialize()
    if init_success:
        print("✅ PASS: Audio driver initialized\n")
    else:
        print("❌ FAIL: Could not initialize audio driver")
        print("   Make sure mpv is installed: choco install mpv\n")
        return False
    
    # Test 2: Search and play music
    test_queries = [
        ("tavern music", "Medieval tavern ambiance"),
        ("epic battle music", "Epic battle orchestral"),
        ("peaceful forest", "Peaceful forest nature sounds"),
    ]
    
    for query, description in test_queries:
        print(f"🎵 TEST 2.{test_queries.index((query, description)) + 1}: {description}")
        print(f"   Query: '{query}'")
        print("-" * 80)
        
        success = await audio.activate({
            'query': query,
            'volume': 0.7
        })
        
        if success:
            print(f"✅ PASS: Audio started playing")
            print(f"   Listening for 15 seconds...")
            await asyncio.sleep(15)
            
            # Stop
            stop_success = await audio.deactivate()
            if stop_success:
                print(f"✅ Stopped playback\n")
            else:
                print(f"⚠️  Could not stop cleanly\n")
        else:
            print(f"❌ FAIL: Could not play audio")
            print(f"   Possible issues:")
            print(f"   - YouTube blocked or yt-dlp outdated: pip install --upgrade yt-dlp")
            print(f"   - Bluetooth speaker not connected")
            print(f"   - Wrong sink name\n")
    
    # Test 3: Volume control
    print("🎵 TEST 3: Volume Control")
    print("-" * 80)
    
    volumes = [0.3, 0.5, 0.8]
    for vol in volumes:
        success = await audio.activate({
            'query': 'tavern music',
            'volume': vol
        })
        
        if success:
            print(f"✅ Volume {int(vol*100)}%: Playing for 3 seconds...")
            await asyncio.sleep(3)
            await audio.deactivate()
        else:
            print(f"❌ Volume {int(vol*100)}%: Failed")
    
    print("\n" + "="*80)
    print("BLUETOOTH SPEAKER TEST COMPLETE".center(80))
    print("="*80)
    print("\n✅ If you heard music on your TG-129C speaker, everything works!\n")
    
    return True


async def test_simple():
    """Simplified test - just play one song"""
    
    print("\n" + "="*80)
    print("QUICK BLUETOOTH TEST".center(80))
    print("="*80 + "\n")
    
    config = DriverConfig(
        driver_id="speaker_1",
        driver_type="audio",
        enabled=True,
        params={
            'sink_name': 'bluez_output.39_3E_58_14_40_4A.1',
            'mpv_path': 'mpv',
            'yt_dlp_path': 'yt-dlp',
        }
    )
    
    audio = AudioDriver(config)
    
    print("🎵 Initializing...")
    if not await audio.initialize():
        print("❌ Failed to initialize mpv")
        return False
    
    print("🔍 Searching YouTube for: 'tavern music'")
    success = await audio.activate({
        'query': 'tavern music',
        'volume': 0.1
    })
    
    if success:
        print("✅ Music started! Listening for 30 seconds...")
        print("   If you hear music on your TG-129C, the test passed!")
        await asyncio.sleep(30)
        await audio.deactivate()
        print("⏹️  Stopped\n")
        return True
    else:
        print("❌ Could not play music\n")
        return False


async def main():
    import sys
    
    if len(sys.argv) > 1 and sys.argv[1] == "--simple":
        # Quick test
        result = await test_simple()
    else:
        # Full test suite
        result = await test_bluetooth_speaker()
    
    return 0 if result else 1


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    sys.exit(exit_code)
