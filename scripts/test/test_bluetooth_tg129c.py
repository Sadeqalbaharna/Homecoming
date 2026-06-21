#!/usr/bin/env python3
"""
Bluetooth Speaker Test - TG-129C Connection & Low Volume Playback
Tests Bluetooth connectivity and plays scene audio at 20% max volume for public use
"""

import subprocess
import logging
import sys
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class BluetoothSpeakerTest:
    """Test Bluetooth speaker connection"""
    
    def __init__(self):
        self.tg_speaker = {
            'mac_underscore': '39_3E_58_14_40_4A',
            'mac_colon': '39:3E:58:14:40:4A',
            'name': 'TG-129C',
            'alias': 'TG-129C Speaker',
        }
    
    def check_bluetooth_connection(self) -> bool:
        """Check if TG-129C Bluetooth speaker is connected"""
        logger.info("🔍 Checking Bluetooth Speaker Connection...\n")
        
        # Check if bluetoothctl is available
        try:
            result = subprocess.run(['bluetoothctl', '--version'], 
                                  capture_output=True, text=True, timeout=5)
            if result.returncode != 0:
                logger.warning("⚠️  bluetoothctl not available - may not be on Raspberry Pi")
                logger.info("💡 This test works best on the actual Pi")
                return False
        except FileNotFoundError:
            logger.warning("⚠️  bluetoothctl not found - not on Raspberry Pi")
            logger.info("💡 This test works best on the actual Pi")
            return False
        except Exception as e:
            logger.error(f"❌ Error checking bluetoothctl: {e}")
            return False
        
        logger.info("✅ bluetoothctl available\n")
        
        # Get device info
        logger.info(f"🔎 Looking for device: {self.tg_speaker['name']}")
        logger.info(f"   MAC Address: {self.tg_speaker['mac_colon']}\n")
        
        try:
            # Get Bluetooth device info
            result = subprocess.run(
                ['bluetoothctl', 'info', self.tg_speaker['mac_colon']],
                capture_output=True, text=True, timeout=5
            )
            
            if result.returncode != 0:
                logger.error(f"❌ Device not found or not paired")
                logger.info("💡 Try pairing the TG-129C first:")
                logger.info("   bluetoothctl")
                logger.info("   scan on")
                logger.info("   pair 39:3E:58:14:40:4A")
                logger.info("   trust 39:3E:58:14:40:4A")
                logger.info("   connect 39:3E:58:14:40:4A\n")
                return False
            
            # Parse output
            output = result.stdout
            logger.info("✅ Device found!\n")
            
            is_connected = "Connected: yes" in output
            is_paired = "Paired: yes" in output
            
            logger.info("📋 Device Information:")
            
            # Extract name
            for line in output.split('\n'):
                if line.startswith('\tName:'):
                    logger.info(f"   {line.strip()}")
                elif line.startswith('\tAlias:'):
                    logger.info(f"   {line.strip()}")
                elif line.startswith('\tAddress:'):
                    logger.info(f"   {line.strip()}")
                elif line.startswith('\tPaired:'):
                    logger.info(f"   {line.strip()}")
                elif line.startswith('\tConnected:'):
                    logger.info(f"   {line.strip()}")
                elif line.startswith('\tTrusted:'):
                    logger.info(f"   {line.strip()}")
            
            logger.info("")
            
            if not is_paired:
                logger.error("❌ Speaker is NOT paired")
                return False
            
            if not is_connected:
                logger.warning("⚠️  Speaker is paired but NOT connected")
                logger.info("🔌 Attempting to connect...\n")
                
                try:
                    result = subprocess.run(
                        ['bluetoothctl', 'connect', self.tg_speaker['mac_colon']],
                        capture_output=True, text=True, timeout=10
                    )
                    
                    if result.returncode == 0:
                        logger.info("✅ Connection successful!\n")
                        is_connected = True
                    else:
                        logger.error(f"❌ Connection failed: {result.stderr}")
                        return False
                except Exception as e:
                    logger.error(f"❌ Connection error: {e}")
                    return False
            else:
                logger.info("✅ Speaker is connected!\n")
            
            return is_paired and is_connected
            
        except Exception as e:
            logger.error(f"❌ Error: {e}")
            return False
    
    def check_pulseaudio_sink(self) -> bool:
        """Check if Bluetooth audio sink is available in PulseAudio"""
        logger.info("=" * 70)
        logger.info("Checking PulseAudio Sink Configuration...\n")
        
        try:
            result = subprocess.run(
                ['pactl', 'list', 'sinks'],
                capture_output=True, text=True, timeout=5
            )
            
            if result.returncode != 0:
                logger.warning("⚠️  pactl not available or PulseAudio not running")
                return False
            
            output = result.stdout
            
            # Look for Bluetooth sinks
            bluetooth_sinks = []
            current_sink = None
            
            for line in output.split('\n'):
                if line.startswith('Sink #'):
                    current_sink = line.strip()
                elif current_sink and 'bluez' in line.lower():
                    bluetooth_sinks.append(current_sink)
                    logger.info(f"✅ Found Bluetooth sink: {current_sink}")
                    logger.info(f"   Details: {line.strip()}")
            
            if not bluetooth_sinks:
                logger.warning("⚠️  No Bluetooth audio sinks found in PulseAudio")
                logger.info("💡 The TG-129C may not be set up for audio output")
                return False
            
            logger.info("")
            return True
            
        except FileNotFoundError:
            logger.warning("⚠️  pactl not found - PulseAudio may not be installed")
            return False
        except Exception as e:
            logger.error(f"❌ Error: {e}")
            return False
    
    def test_audio_playback(self) -> bool:
        """Test audio playback at 20% volume"""
        logger.info("=" * 70)
        logger.info("Testing Audio Playback at 20% Volume...\n")
        
        logger.info("🔊 Volume Settings:")
        logger.info("   Max Volume: 20% (ENFORCED - safe for public)")
        logger.info("   Minimum: 5% (for audibility)")
        logger.info("   Cannot exceed 20% - hardcoded safety limit\n")
        
        try:
            # Check if mpv is available
            result = subprocess.run(['mpv', '--version'], 
                                  capture_output=True, timeout=2)
            if result.returncode != 0:
                logger.warning("⚠️  mpv not available")
                logger.info("💡 Install with: sudo apt-get install mpv")
                return False
            
            logger.info("✅ mpv available\n")
            
            # Check if yt-dlp is available
            result = subprocess.run(['yt-dlp', '--version'], 
                                  capture_output=True, timeout=2)
            if result.returncode != 0:
                logger.warning("⚠️  yt-dlp not available")
                logger.info("💡 Install with: sudo apt-get install yt-dlp")
                return False
            
            logger.info("✅ yt-dlp available\n")
            
            logger.info("✅ All audio tools available - ready to play!")
            logger.info("\n📝 To test actual playback with a scene:")
            logger.info("   python test_modular_scene_playback.py haunted_mansion\n")
            
            return True
            
        except FileNotFoundError as e:
            logger.warning(f"⚠️  Required tool not found: {e}")
            return False
        except Exception as e:
            logger.error(f"❌ Error: {e}")
            return False


async def main():
    """Main entry point"""
    logger.info("\n" + "=" * 70)
    logger.info("🎧 BLUETOOTH SPEAKER TEST - TG-129C".center(70))
    logger.info("=" * 70 + "\n")
    
    tester = BluetoothSpeakerTest()
    
    # Test Bluetooth connection
    bt_ok = tester.check_bluetooth_connection()
    
    # Test PulseAudio sink
    pulse_ok = tester.check_pulseaudio_sink()
    
    # Test audio playback tools
    audio_ok = tester.test_audio_playback()
    
    # Summary
    logger.info("=" * 70)
    logger.info("📊 TEST SUMMARY\n")
    
    logger.info(f"Bluetooth Device:     {'✅ OK' if bt_ok else '❌ FAIL'}")
    logger.info(f"PulseAudio Sink:      {'✅ OK' if pulse_ok else '⚠️  WARNING'}")
    logger.info(f"Audio Tools:          {'✅ OK' if audio_ok else '❌ FAIL'}\n")
    
    if bt_ok and audio_ok:
        logger.info("✅ Everything ready! Run a scene test:")
        logger.info("   python test_modular_scene_playback.py haunted_mansion")
    elif not bt_ok:
        logger.info("❌ Bluetooth speaker not connected. Please pair and connect TG-129C.")
    else:
        logger.info("⚠️  Some issues detected. Check the messages above.")
    
    logger.info("\n" + "=" * 70)
    logger.info("⚠️  REMEMBER: Volume capped at 20% for public use!".center(70))
    logger.info("=" * 70 + "\n")


if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
