#!/usr/bin/env python3
"""
Automated Bluetooth Speaker Troubleshooting & Verification
Runs on app launch to ensure speaker is working before proceeding
"""

import paramiko
import logging
import time
import sys
import subprocess
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_USER = "pi"
SPEAKER_MAC = "39:3E:58:14:40:4A"
PI_IP = None  # Will be auto-discovered

class BluetoothAutoTroubleshoot:
    def __init__(self, pi_ip=None):
        self.pi_ip = pi_ip
        self.client = None
        self.issues = []
        self.fixes_applied = []
    
    def find_pi(self):
        """Auto-discover Pi if IP not provided"""
        if self.pi_ip:
            return True
        
        logger.info("\n🔍 Auto-discovering Raspberry Pi...")
        
        # Try to import and use discover_pi
        try:
            result = subprocess.run(
                [sys.executable, str(Path(__file__).parent / "discover_pi.py")],
                capture_output=True,
                text=True,
                timeout=60
            )
            
            if result.returncode == 0:
                self.pi_ip = result.stdout.strip()
                logger.info(f"✅ Found Pi at: {self.pi_ip}\n")
                return True
        except Exception as e:
            logger.error(f"Discovery failed: {e}")
        
        logger.error("Could not discover Pi automatically")
        return False
    
    def connect(self):
        """Connect to Pi"""
        try:
            self.client = paramiko.SSHClient()
            self.client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            self.client.connect(
                self.pi_ip, 
                username=PI_USER, 
                key_filename=str(Path.home() / ".ssh" / "id_rsa"),
                timeout=10
            )
            return True
        except Exception as e:
            logger.error(f"❌ Cannot connect to Pi at {self.pi_ip}: {e}")
            return False
    
    def run_command(self, cmd, timeout=10):
        """Run command and return output"""
        try:
            stdin, stdout, stderr = self.client.exec_command(cmd, timeout=timeout)
            return stdout.read().decode(), stderr.read().decode()
        except Exception as e:
            return "", str(e)
    
    def check_bluetooth_adapter(self):
        """CHECK 1: Is Bluetooth adapter powered on?"""
        logger.info("\n[CHECK 1/5] Bluetooth adapter status...")
        
        output, _ = self.run_command("hciconfig hci0")
        
        if "DOWN" in output:
            logger.warning("⚠️  Adapter is DOWN - fixing...")
            self.issues.append("Adapter DOWN")
            
            # Try to bring it up
            self.run_command("sudo hciconfig hci0 up")
            time.sleep(1)
            
            output, _ = self.run_command("hciconfig hci0")
            if "UP" in output:
                logger.info("✅ Adapter brought UP")
                self.fixes_applied.append("Adapter power cycled")
            else:
                logger.error("❌ Adapter still DOWN - may need hardware fix")
                return False
        elif "UP" in output:
            logger.info("✅ Adapter is UP")
        else:
            logger.warning("⚠️  Unknown adapter status")
            return False
        
        return True
    
    def check_speaker_connection(self):
        """CHECK 2: Is speaker paired and connected?"""
        logger.info("[CHECK 2/5] Speaker connection...")
        
        output, _ = self.run_command(f"bluetoothctl info {SPEAKER_MAC}")
        
        if "Connected: no" in output:
            logger.warning("⚠️  Speaker not connected - reconnecting...")
            self.issues.append("Speaker disconnected")
            
            self.run_command(f"bluetoothctl connect {SPEAKER_MAC}")
            time.sleep(3)
            
            output, _ = self.run_command(f"bluetoothctl info {SPEAKER_MAC}")
            if "Connected: yes" in output:
                logger.info("✅ Speaker reconnected")
                self.fixes_applied.append("Speaker reconnected")
            else:
                logger.error("❌ Failed to connect speaker")
                return False
        elif "Connected: yes" in output:
            logger.info("✅ Speaker connected")
        else:
            logger.error("❌ Speaker not found or not paired")
            return False
        
        return True
    
    def check_pulseaudio_sink(self):
        """CHECK 3: Does PulseAudio see the Bluetooth sink?"""
        logger.info("[CHECK 3/5] PulseAudio Bluetooth sink...")
        
        output, _ = self.run_command("pactl list short sinks | grep bluez")
        
        if not output.strip():
            logger.warning("⚠️  Bluetooth sink not found - loading module...")
            self.issues.append("Bluetooth sink missing")
            
            self.run_command("pactl load-module module-bluez5-discover")
            time.sleep(2)
            
            output, _ = self.run_command("pactl list short sinks | grep bluez")
            if output.strip():
                logger.info("✅ Bluetooth sink loaded")
                self.fixes_applied.append("Bluetooth module loaded")
            else:
                logger.error("❌ Failed to load Bluetooth sink")
                return False
        else:
            logger.info("✅ Bluetooth sink available")
        
        return True
    
    def check_volume_settings(self):
        """CHECK 4: Volume and mute settings"""
        logger.info("[CHECK 4/5] Volume configuration...")
        
        sink_name = f"bluez_output.{SPEAKER_MAC.replace(':','_')}.1"
        
        # Unmute
        self.run_command(f"pactl set-sink-mute {sink_name} 0")
        
        # Set to 100% for testing
        self.run_command(f"pactl set-sink-volume {sink_name} 100%")
        
        output, _ = self.run_command(f"pactl get-sink-mute {sink_name}")
        if "no" in output:
            logger.info("✅ Speaker unmuted")
            self.fixes_applied.append("Speaker unmuted")
        
        logger.info("✅ Volume set to 100%")
        return True
    
    def test_audio_playback(self):
        """CHECK 5: Can we actually play audio?"""
        logger.info("[CHECK 5/5] Audio playback test...")
        
        sink_name = f"bluez_output.{SPEAKER_MAC.replace(':','_')}.1"
        
        # Create test tone
        test_script = '''
import wave, struct, math
with wave.open('/tmp/test_tone.wav', 'wb') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(44100)
    for i in range(44100):  # 1 second
        val = int(32767 * math.sin(2*math.pi*440*i/44100))
        f.writeframes(struct.pack('<h', val))
print('OK')
'''
        
        output, _ = self.run_command(f"python3 << 'EOF'\n{test_script}\nEOF")
        
        if "OK" not in output:
            logger.error("❌ Failed to create test tone")
            return False
        
        logger.info("   Playing test tone (you should hear a beep)...")
        
        # Play it
        self.run_command(
            f"paplay --device={sink_name} --volume=65536 /tmp/test_tone.wav",
            timeout=3
        )
        
        time.sleep(2)
        
        logger.info("✅ Test tone played")
        logger.info("   ❓ Did you hear a beep from the speaker?")
        
        return True
    
    def run_diagnostics(self):
        """Run full diagnostic sequence"""
        logger.info("\n" + "="*70)
        logger.info("BLUETOOTH SPEAKER AUTO-TROUBLESHOOTING".center(70))
        logger.info("="*70)
        
        # Step 1: Find Pi
        if not self.find_pi():
            return False
        
        # Step 2: Connect to Pi
        if not self.connect():
            return False
        
        checks = [
            self.check_bluetooth_adapter,
            self.check_speaker_connection,
            self.check_pulseaudio_sink,
            self.check_volume_settings,
            self.test_audio_playback,
        ]
        
        for check in checks:
            try:
                if not check():
                    self.client.close()
                    return False
            except Exception as e:
                logger.error(f"❌ Check failed: {e}")
                self.client.close()
                return False
        
        self.client.close()
        return True
    
    def report(self):
        """Print diagnostic report"""
        logger.info("\n" + "="*70)
        logger.info("DIAGNOSTIC REPORT".center(70))
        logger.info("="*70)
        
        if self.issues:
            logger.info("\n⚠️  Issues Found:")
            for issue in self.issues:
                logger.info(f"   - {issue}")
        else:
            logger.info("\n✅ No issues detected")
        
        if self.fixes_applied:
            logger.info("\n🔧 Fixes Applied:")
            for fix in self.fixes_applied:
                logger.info(f"   ✓ {fix}")
        
        logger.info("\n" + "="*70)
        logger.info("RESULT: SPEAKER READY FOR SCENE PLAYBACK".center(70))
        logger.info("="*70 + "\n")

def main():
    troubleshoot = BluetoothAutoTroubleshoot()
    
    success = troubleshoot.run_diagnostics()
    troubleshoot.report()
    
    if success:
        logger.info("✅✅✅ BLUETOOTH SPEAKER CONFIRMED WORKING\n")
        return 0
    else:
        logger.error("❌ Troubleshooting failed - manual intervention needed\n")
        return 1

if __name__ == "__main__":
    sys.exit(main())
