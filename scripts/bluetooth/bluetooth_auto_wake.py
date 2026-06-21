#!/usr/bin/env python3
"""
Bluetooth Speaker Auto-Wake Module
Automatically wakes up and connects Bluetooth speaker before scene playback
"""

import subprocess
import logging
import time
from typing import Tuple

logger = logging.getLogger(__name__)

class BluetoothAutoWake:
    """Auto-wake and verify Bluetooth speaker"""
    
    MAC_ADDRESS = "39:3E:58:14:40:4A"
    DEVICE_NAME = "TG-129C"
    SINK_NAME = "bluez_output.39_3E_58_14_40_4A.1"
    
    @staticmethod
    def wake_up() -> bool:
        """
        Wake up Bluetooth speaker - full pipeline
        Returns: True if successful, False if failed
        """
        logger.info("")
        logger.info("=" * 70)
        logger.info("🔋 BLUETOOTH AUTO-WAKE SEQUENCE".center(70))
        logger.info("=" * 70)
        logger.info("")
        
        # Step 0: Reset Bluetooth completely
        logger.info("Step 0: Resetting Bluetooth service...")
        try:
            subprocess.run(
                ["systemctl", "--user", "restart", "bluetooth"],
                timeout=5, capture_output=True
            )
            time.sleep(2)
            logger.info("✅ Bluetooth service reset")
        except Exception as e:
            logger.warning(f"⚠️  Could not restart Bluetooth service: {e}")
        
        time.sleep(1)
        
        # Step 1: Turn on Bluetooth adapter
        logger.info("Step 1: Enabling Bluetooth adapter...")
        try:
            subprocess.run(
                ["bluetoothctl", "power", "on"],
                timeout=5, capture_output=True
            )
            logger.info("✅ Bluetooth adapter on")
        except Exception as e:
            logger.warning(f"⚠️  Could not enable Bluetooth: {e}")
        
        time.sleep(1)
        
        # Step 2: Connect to speaker
        logger.info("Step 2: Connecting to TG-129C speaker...")
        try:
            result = subprocess.run(
                ["bluetoothctl", "connect", BluetoothAutoWake.MAC_ADDRESS],
                timeout=10, capture_output=True, text=True
            )
            
            if "Connection successful" in result.stdout or result.returncode == 0:
                logger.info(f"✅ Connected to {BluetoothAutoWake.DEVICE_NAME}")
            else:
                logger.warning(f"⚠️  Connection attempt: {result.stdout}")
                logger.info("   (This is normal if speaker needs time to respond)")
        except Exception as e:
            logger.warning(f"⚠️  Connection error: {e}")
        
        time.sleep(2)
        
        # Step 3: Ensure PulseAudio Bluetooth module is loaded
        logger.info("Step 3: Loading PulseAudio Bluetooth module...")
        try:
            # Unload first to reset
            subprocess.run(
                ["pactl", "unload-module", "module-bluez5-discover"],
                timeout=5, capture_output=True
            )
            time.sleep(1)
            
            # Load fresh
            result = subprocess.run(
                ["pactl", "load-module", "module-bluez5-discover"],
                timeout=5, capture_output=True, text=True
            )
            logger.info("✅ PulseAudio Bluetooth module loaded")
        except Exception as e:
            logger.warning(f"⚠️  PulseAudio module error: {e}")
        
        time.sleep(2)
        
        # Step 4: Verify sink is available
        logger.info("Step 4: Verifying PulseAudio sink...")
        try:
            result = subprocess.run(
                ["pactl", "get-sink-mute", BluetoothAutoWake.SINK_NAME],
                timeout=5, capture_output=True, text=True
            )
            
            if result.returncode == 0:
                logger.info(f"✅ PulseAudio sink ready: {BluetoothAutoWake.SINK_NAME}")
            else:
                logger.warning(f"⚠️  Sink not responding yet, trying default...")
                # Fall back to system audio
        except Exception as e:
            logger.warning(f"⚠️  Sink check error: {e}")
        
        # Step 5: Unmute and set volume to max
        logger.info("Step 5: Configuring audio output...")
        try:
            # Unmute
            subprocess.run(
                ["pactl", "set-sink-mute", BluetoothAutoWake.SINK_NAME, "0"],
                timeout=5, capture_output=True
            )
            
            # Set volume to 100% (we'll control volume via mpv)
            subprocess.run(
                ["pactl", "set-sink-volume", BluetoothAutoWake.SINK_NAME, "100%"],
                timeout=5, capture_output=True
            )
            
            logger.info("✅ Audio output configured (unmuted, volume ready)")
        except Exception as e:
            logger.warning(f"⚠️  Audio config error: {e}")
        
        time.sleep(1)
        
        # Step 6: Final verification
        logger.info("Step 6: Final verification...")
        try:
            # Check Bluetooth device is connected
            result = subprocess.run(
                ["bluetoothctl", "info", BluetoothAutoWake.MAC_ADDRESS],
                timeout=5, capture_output=True, text=True
            )
            
            if "Connected: yes" in result.stdout:
                logger.info(f"✅ Bluetooth speaker CONNECTED and ready")
                logger.info("")
                logger.info("=" * 70)
                logger.info("🎵 BLUETOOTH READY FOR SCENE PLAYBACK".center(70))
                logger.info("=" * 70)
                logger.info("")
                return True
            else:
                logger.warning(f"⚠️  Speaker may not be connected")
                logger.info("Attempting manual reconnect...")
                
                # Try one more time
                subprocess.run(
                    ["bluetoothctl", "connect", BluetoothAutoWake.MAC_ADDRESS],
                    timeout=10, capture_output=True
                )
                time.sleep(3)
                
                result = subprocess.run(
                    ["bluetoothctl", "info", BluetoothAutoWake.MAC_ADDRESS],
                    timeout=5, capture_output=True, text=True
                )
                
                if "Connected: yes" in result.stdout:
                    logger.info(f"✅ Successfully connected on retry")
                    logger.info("")
                    return True
                else:
                    logger.error(f"❌ Failed to connect speaker")
                    logger.error("   Make sure TG-129C is powered on and in Bluetooth pairing mode")
                    logger.info("")
                    return False
        
        except Exception as e:
            logger.error(f"❌ Verification error: {e}")
            return False
    
    @staticmethod
    def check_status() -> dict:
        """Check current Bluetooth and PulseAudio status"""
        status = {
            "bluetooth_connected": False,
            "pulseaudio_sink": False,
            "ready": False
        }
        
        try:
            # Check Bluetooth
            result = subprocess.run(
                ["bluetoothctl", "info", BluetoothAutoWake.MAC_ADDRESS],
                timeout=5, capture_output=True, text=True
            )
            status["bluetooth_connected"] = "Connected: yes" in result.stdout
            
            # Check PulseAudio sink
            result = subprocess.run(
                ["pactl", "get-sink-mute", BluetoothAutoWake.SINK_NAME],
                timeout=5, capture_output=True, text=True
            )
            status["pulseaudio_sink"] = result.returncode == 0
            
            # Overall ready status
            status["ready"] = status["bluetooth_connected"] and status["pulseaudio_sink"]
        
        except Exception as e:
            logger.debug(f"Status check error: {e}")
        
        return status


def ensure_bluetooth_ready():
    """
    Main function: Ensure Bluetooth is ready, wake up if needed
    Call this before EVERY scene playback
    """
    # Check current status
    status = BluetoothAutoWake.check_status()
    
    if status["ready"]:
        logger.info("🔋 Bluetooth already connected and ready")
        return True
    else:
        logger.info("🔋 Bluetooth not ready, starting wake-up sequence...")
        return BluetoothAutoWake.wake_up()


if __name__ == "__main__":
    # Test the auto-wake
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )
    
    success = ensure_bluetooth_ready()
    
    if success:
        logger.info("\n✅ Bluetooth is ready for scenes!")
    else:
        logger.error("\n❌ Bluetooth wake-up failed - check speaker and try again")
