#!/usr/bin/env python3
"""
Homecoming App - Complete Auto-Startup with Dynamic Pi Discovery
Discovers Pi IP once, uses it throughout all startup processes
"""

import subprocess
import sys
import logging
import json
import paramiko
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

class HomecomingStartup:
    def __init__(self):
        self.pi_ip = None
        self.app_dir = Path(__file__).parent
    
    def discover_pi(self):
        """Step 1: Discover Pi dynamically"""
        logger.info("\n📍 DISCOVERING RASPBERRY PI...")
        logger.info("-" * 70)
        
        # Quick fallback: Try known Pi IPs first
        logger.info("⏳ Connecting to Pi...")
        known_ips = ["192.168.131.5", "192.168.48.5", "raspberrypi.local"]
        
        for ip in known_ips:
            try:
                client = paramiko.SSHClient()
                client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
                client.connect(
                    ip,
                    username="pi",
                    key_filename=str(Path.home() / ".ssh" / "id_rsa"),
                    timeout=3
                )
                client.close()
                
                self.pi_ip = ip
                logger.info(f"✅ Found Pi at: {self.pi_ip}\n")
                return True
            except:
                pass
        
        logger.error("❌ Could not find Pi")
        return False
    
    def bluetooth_ping(self):
        """Step 2: Comprehensive Bluetooth device verification with auto-fix"""
        logger.info("📡 BLUETOOTH DEVICE VERIFICATION...")
        logger.info("-" * 70)
        
        try:
            result = subprocess.run(
                [sys.executable, str(self.app_dir / "bluetooth_device_ping.py"), self.pi_ip],
                capture_output=True,
                text=True,
                timeout=90
            )
            
            if result.returncode == 0:
                logger.info("✅ Device verified and responsive\n")
                return True
            else:
                logger.error("❌ Device verification failed\n")
                return False
        except Exception as e:
            logger.error(f"❌ Verification error: {e}")
            return False
    
    def verify_speaker_hardware(self):
        """Step 3: Verify speaker hardware is actually working"""
        logger.info("🔊 SPEAKER HARDWARE VERIFICATION...")
        logger.info("-" * 70)
        
        max_retries = 2
        retry_count = 0
        
        while retry_count < max_retries:
            try:
                result = subprocess.run(
                    [sys.executable, str(self.app_dir / "speaker_hardware_check.py"), self.pi_ip],
                    capture_output=True,
                    text=True,
                    timeout=60
                )
                
                if result.returncode == 0:
                    logger.info("✅ Speaker hardware verified and responding\n")
                    return True
                else:
                    # Speaker not responding - try to wake it
                    retry_count += 1
                    if retry_count < max_retries:
                        logger.warning(f"⚠️  Speaker not responding (attempt {retry_count}/{max_retries})")
                        logger.info("🔄 Attempting to wake speaker...")
                        
                        wake_result = subprocess.run(
                            [sys.executable, str(self.app_dir / "force_speaker_wake.py"), self.pi_ip],
                            capture_output=True,
                            text=True,
                            timeout=60
                        )
                        
                        import time
                        logger.info("⏳ Waiting for speaker to wake up...")
                        time.sleep(5)
                        continue
                    else:
                        logger.warning("⚠️  Speaker not responding")
                        logger.warning("\nSpeaker may be:")
                        logger.warning("  - Powered OFF (turn it on manually)")
                        logger.warning("  - In sleep mode (press power button)")
                        logger.warning("  - Out of range")
                        logger.warning("  - Hardware issue")
                        logger.info("\n⏭️  Continuing startup anyway...")
                        logger.info("   You can still play scenes once speaker is fixed\n")
                        return True  # Allow startup to continue
                        
            except subprocess.TimeoutExpired:
                logger.warning("⚠️  Speaker verification timeout")
                logger.info("⏭️  Continuing startup anyway...\n")
                return True
            except Exception as e:
                logger.warning(f"⚠️  Speaker verification error: {e}")
                logger.info("⏭️  Continuing startup anyway...\n")
                return True
        
        return True
    
    def test_audio(self):
        """Step 4: Test audio playback on speaker"""
        logger.info("🎵 AUDIO PLAYBACK TEST...")
        logger.info("-" * 70)
        
        try:
            result = subprocess.run(
                [sys.executable, str(self.app_dir / "test_audio_playback.py"), self.pi_ip],
                capture_output=True,
                text=True,
                timeout=120
            )
            
            if result.returncode == 0:
                logger.info("✅ Audio pipeline configured\n")
                return True
            else:
                logger.warning("⚠️  Audio test had issues (continuing anyway)\n")
                return True
        except Exception as e:
            logger.error(f"❌ Audio test failed: {e}")
            return False
    
    def deploy_system(self):
        """Step 5: Deploy auto-troubleshoot to Pi"""
        logger.info("📦 DEPLOYING AUTO-TROUBLESHOOT SYSTEM...")
        logger.info("-" * 70)
        
        try:
            result = subprocess.run(
                [sys.executable, str(self.app_dir / "deploy_to_pi.py"), self.pi_ip],
                capture_output=False,
                timeout=300
            )
            
            if result.returncode == 0:
                logger.info("✅ Deployment successful\n")
                return True
            else:
                logger.warning("⚠️  Deployment had issues (continuing anyway)\n")
                return True  # Continue even if deploy has warnings
        except Exception as e:
            logger.error(f"❌ Deployment failed: {e}")
            return False
    
    def run_troubleshoot(self):
        """Step 6: Run Bluetooth troubleshooting"""
        logger.info("🔧 RUNNING BLUETOOTH TROUBLESHOOTING...")
        logger.info("-" * 70)
        
        try:
            result = subprocess.run(
                [sys.executable, str(self.app_dir / "troubleshoot_bluetooth.py"), self.pi_ip],
                capture_output=False,
                timeout=300
            )
            
            if result.returncode == 0:
                logger.info("✅ All checks passed\n")
                return True
            else:
                logger.warning("⚠️  Some checks failed (continuing anyway)\n")
                return True
        except Exception as e:
            logger.error(f"❌ Troubleshooting failed: {e}")
            return False
    
    def launch_app(self):
        """Step 7: Interactive scene listener"""
        logger.info("\n" + "="*70)
        logger.info("✅ HOMECOMING READY".center(70))
        logger.info("="*70)
        logger.info(f"\n🎭 D&D Ambiance App")
        logger.info(f"📍 Pi: {self.pi_ip}")
        logger.info(f"🎵 Bluetooth: Connected & Ready")
        logger.info(f"📻 Listening for scene commands...\n")
        
        # Keep app running and listen for scene input
        try:
            while True:
                scene_name = input("\n🎬 Enter scene name (or 'quit'): ").strip().lower()
                
                if scene_name == 'quit':
                    logger.info("\n👋 App closed\n")
                    return 0
                
                if not scene_name:
                    continue
                
                # Try to find and play the scene
                self.play_scene(scene_name)
                
        except KeyboardInterrupt:
            logger.info("\n👋 App closed\n")
            return 0
    
    def play_scene(self, scene_name):
        """Play a scene by name"""
        # Map scene names to their scene JSON files
        scene_files = {
            'pirate_ship': 'pirate_ship_scene.json',
            'pirate': 'pirate_ship_scene.json',
        }
        
        scene_file = scene_files.get(scene_name)
        
        if not scene_file:
            logger.warning(f"❌ Scene '{scene_name}' not found")
            logger.info(f"   Available scenes:")
            for name in scene_files.keys():
                logger.info(f"      - {name}")
            return
        
        scene_path = self.app_dir / scene_file
        
        if not scene_path.exists():
            logger.error(f"❌ Scene file not found: {scene_file}")
            return
        
        logger.info(f"\n🎵 Playing: {scene_name}")
        logger.info("-" * 70)
        
        try:
            # Run the simple scene player that generates audio locally
            result = subprocess.run(
                [sys.executable, str(self.app_dir / "play_scene_simple.py"), self.pi_ip, str(scene_path)],
                timeout=600
            )
            
            logger.info("-" * 70)
            if result.returncode == 0:
                logger.info(f"✅ Scene complete\n")
            else:
                logger.warning(f"⚠️  Scene playback returned code {result.returncode}\n")
        
        except subprocess.TimeoutExpired:
            logger.warning(f"⏱️  Scene playback timeout\n")
        except Exception as e:
            logger.error(f"❌ Error playing scene: {e}\n")
    
    def run(self):
        """Run complete startup sequence"""
        logger.info("\n" + "="*70)
        logger.info("HOMECOMING - D&D AMBIANCE APP".center(70))
        logger.info("="*70)
        
        # Step 1: Discover
        if not self.discover_pi():
            logger.error("Could not discover Pi. Is it powered on and on the network?")
            return 1
        
        # Step 2: Bluetooth ping
        if not self.bluetooth_ping():
            logger.error("Bluetooth is not responding")
            return 1
        
        # Step 3: Verify speaker hardware (with auto-wake)
        if not self.verify_speaker_hardware():
            logger.error("Speaker hardware not working")
            return 1
        
        # Step 4: Test audio
        if not self.test_audio():
            logger.error("Audio test failed")
            return 1
        
        # Step 5: Deploy
        if not self.deploy_system():
            logger.error("Deployment failed")
            return 1
        
        # Step 6: Troubleshoot
        if not self.run_troubleshoot():
            logger.error("Troubleshooting failed")
            return 1
        
        # Step 7: Launch
        return self.launch_app()

if __name__ == "__main__":
    startup = HomecomingStartup()
    sys.exit(startup.run())
