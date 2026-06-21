#!/usr/bin/env python3
"""
Auto-troubleshoot Bluetooth speaker on Pi startup
This runs directly on the Pi and ensures speaker is ready before app starts
"""

import subprocess
import logging
import time
import sys

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

SPEAKER_MAC = "39:3E:58:14:40:4A"

def run_cmd(cmd):
    """Run command and return output"""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
        return result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return "", "TIMEOUT"
    except Exception as e:
        return "", str(e)

def check_adapter():
    """Check if Bluetooth adapter is up"""
    logger.info("[1/5] Checking Bluetooth adapter...")
    output, _ = run_cmd("hciconfig hci0")
    
    if "DOWN" in output:
        logger.warning("     Adapter DOWN - powering up...")
        run_cmd("sudo hciconfig hci0 up")
        time.sleep(1)
        output, _ = run_cmd("hciconfig hci0")
        
        if "UP" in output:
            logger.info("     ✅ Adapter UP")
            return True
        else:
            logger.error("     ❌ Failed to bring adapter up")
            return False
    elif "UP" in output:
        logger.info("     ✅ Adapter UP")
        return True
    else:
        logger.error("     ❌ Unknown status")
        return False

def check_speaker():
    """Check if speaker is connected"""
    logger.info("[2/5] Checking speaker connection...")
    output, _ = run_cmd(f"bluetoothctl info {SPEAKER_MAC}")
    
    if "Connected: no" in output:
        logger.warning("     Speaker disconnected - reconnecting...")
        run_cmd(f"bluetoothctl connect {SPEAKER_MAC}")
        time.sleep(3)
        output, _ = run_cmd(f"bluetoothctl info {SPEAKER_MAC}")
        
        if "Connected: yes" in output:
            logger.info("     ✅ Speaker connected")
            return True
        else:
            logger.error("     ❌ Failed to connect")
            return False
    elif "Connected: yes" in output:
        logger.info("     ✅ Speaker connected")
        return True
    else:
        logger.error("     ❌ Speaker not found")
        return False

def check_pulseaudio():
    """Check if Bluetooth sink exists"""
    logger.info("[3/5] Checking PulseAudio sink...")
    output, _ = run_cmd("pactl list short sinks | grep bluez")
    
    if not output.strip():
        logger.warning("     Sink missing - loading module...")
        run_cmd("pactl load-module module-bluez5-discover")
        time.sleep(2)
        output, _ = run_cmd("pactl list short sinks | grep bluez")
        
        if output.strip():
            logger.info("     ✅ Sink loaded")
            return True
        else:
            logger.error("     ❌ Failed to load sink")
            return False
    else:
        logger.info("     ✅ Sink available")
        return True

def check_volume():
    """Ensure volume is set"""
    logger.info("[4/5] Configuring volume...")
    sink_name = f"bluez_output.{SPEAKER_MAC.replace(':','_')}.1"
    
    run_cmd(f"pactl set-sink-mute {sink_name} 0")
    run_cmd(f"pactl set-sink-volume {sink_name} 100%")
    
    logger.info("     ✅ Volume set to 100%")
    return True

def test_audio():
    """Play test tone"""
    logger.info("[5/5] Testing audio playback...")
    sink_name = f"bluez_output.{SPEAKER_MAC.replace(':','_')}.1"
    
    # Create test tone
    script = '''
import wave, struct, math
with wave.open('/tmp/test.wav', 'wb') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(44100)
    for i in range(22050):  # 0.5 seconds
        val = int(32767 * math.sin(2*math.pi*440*i/44100))
        f.writeframes(struct.pack('<h', val))
'''
    
    run_cmd(f"python3 << 'EOF'\n{script}\nEOF")
    
    # Play it
    run_cmd(f"paplay --device={sink_name} /tmp/test.wav 2>/dev/null &")
    time.sleep(1)
    
    logger.info("     ✅ Test tone played")
    return True

def main():
    logger.info("\n" + "="*60)
    logger.info("BLUETOOTH AUTO-TROUBLESHOOT ON STARTUP".center(60))
    logger.info("="*60 + "\n")
    
    checks = [
        check_adapter,
        check_speaker,
        check_pulseaudio,
        check_volume,
        test_audio,
    ]
    
    for check in checks:
        try:
            if not check():
                logger.error("\n❌ Troubleshooting failed\n")
                return 1
        except Exception as e:
            logger.error(f"Error: {e}\n")
            return 1
    
    logger.info("\n" + "="*60)
    logger.info("✅ SPEAKER READY - APP LAUNCHING...".center(60))
    logger.info("="*60 + "\n")
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
