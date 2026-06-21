#!/usr/bin/env python3
"""
SSH to Pi and activate a D&D scene on Bluetooth speaker
Uses paramiko for SSH connections (cross-platform Python)
"""

import sys
import time
import logging
from pathlib import Path

# Try importing paramiko for SSH
try:
    import paramiko
    HAS_PARAMIKO = True
except ImportError:
    HAS_PARAMIKO = False
    print("⚠️  paramiko not installed. Install with: pip install paramiko")

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

# Configuration
PI_IP = "192.168.48.5"
PI_USER = "pi"
PI_PASS = "raspberry"  # Default Pi password

SCENES = {
    "haunted_mansion": "haunted mansion spooky ambiance music",
    "dungeon": "dark dungeon D&D ambiance music",
    "forest": "ancient forest magical adventure music",
    "tavern": "medieval tavern D&D background music",
    "battle": "epic battle D&D combat music",
}


def activate_scene_via_ssh(scene_name: str, pi_ip: str = PI_IP, username: str = PI_USER):
    """
    SSH to Pi and activate a scene
    
    Args:
        scene_name: Scene to activate (haunted_mansion, dungeon, forest, tavern, battle)
        pi_ip: IP address of Raspberry Pi
        username: SSH username
    """
    
    if not HAS_PARAMIKO:
        logger.error("❌ paramiko not available - cannot SSH")
        logger.info("💡 Install with: pip install paramiko")
        return False
    
    if scene_name not in SCENES:
        logger.error(f"❌ Unknown scene: {scene_name}")
        logger.info(f"Available: {', '.join(SCENES.keys())}")
        return False
    
    logger.info("\n" + "="*70)
    logger.info(f"🎭 ACTIVATING SCENE: {scene_name.upper()}".center(70))
    logger.info(f"📍 Target: {username}@{pi_ip}".center(70))
    logger.info("="*70 + "\n")
    
    try:
        # Create SSH client
        logger.info("🔌 Connecting to Pi via SSH...")
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        
        # Connect
        ssh.connect(pi_ip, username=username, password=PI_PASS, timeout=10)
        logger.info("✅ SSH connection established\n")
        
        # Check if test script exists
        logger.info("🔍 Checking for test script...")
        stdin, stdout, stderr = ssh.exec_command("ls test_modular_scene_playback.py 2>/dev/null")
        stdout.channel.recv_exit_status()
        
        if stdout.channel.recv_exit_status() != 0:
            logger.warning("⚠️  test_modular_scene_playback.py not found on Pi")
            logger.info("💡 Need to deploy files first")
            logger.info("   Use: python prepare_pi_deployment.py")
            ssh.close()
            return False
        
        logger.info("✅ Test script found\n")
        
        # Run the scene activation
        logger.info(f"🎵 Activating {scene_name} scene...")
        logger.info("⚠️  VOLUME: 20% MAX (CAPPED FOR PUBLIC SAFETY)\n")
        
        command = f"cd /home/{username} && python test_modular_scene_playback.py {scene_name}"
        
        logger.info(f"📋 Command: {command}\n")
        logger.info("="*70)
        logger.info("LIVE OUTPUT FROM PI:")
        logger.info("="*70 + "\n")
        
        # Execute and stream output
        stdin, stdout, stderr = ssh.exec_command(command)
        
        # Read output in real-time
        for line in stdout:
            print(line.rstrip())
        
        # Check for errors
        stderr_text = stderr.read().decode()
        if stderr_text:
            logger.error(f"\n⚠️  Errors:\n{stderr_text}")
        
        exit_code = stdout.channel.recv_exit_status()
        
        logger.info("\n" + "="*70)
        if exit_code == 0:
            logger.info("✅ Scene activated successfully!".center(70))
        else:
            logger.error(f"⚠️  Exit code: {exit_code}".center(70))
        logger.info("="*70 + "\n")
        
        # Close connection
        ssh.close()
        logger.info("🔌 SSH connection closed\n")
        
        return exit_code == 0
        
    except paramiko.ssh_exception.NoValidConnectionsError:
        logger.error(f"❌ Cannot connect to {pi_ip}:22")
        logger.info("💡 Make sure:")
        logger.info("   - Pi is powered on and on the network")
        logger.info(f"   - Pi's IP is correct: {pi_ip}")
        logger.info("   - SSH is enabled on Pi")
        return False
    except paramiko.ssh_exception.AuthenticationException:
        logger.error(f"❌ Authentication failed for {username}@{pi_ip}")
        logger.info("💡 Check username and password")
        return False
    except Exception as e:
        logger.error(f"❌ Error: {e}")
        return False


def main():
    """Main entry point"""
    logger.info("\n🎭 SCENE ACTIVATION VIA SSH")
    logger.info("-" * 70)
    
    # Get scene from command line
    if len(sys.argv) < 2:
        logger.info("Available scenes:")
        for i, scene in enumerate(SCENES.keys(), 1):
            logger.info(f"  {i}. {scene}")
        logger.info("\nUsage: python ssh_scene_activator.py <scene_name>")
        logger.info("Example: python ssh_scene_activator.py haunted_mansion\n")
        sys.exit(1)
    
    scene = sys.argv[1]
    
    # Optional: Custom Pi IP
    pi_ip = sys.argv[2] if len(sys.argv) > 2 else PI_IP
    
    # Activate scene
    success = activate_scene_via_ssh(scene, pi_ip=pi_ip)
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
