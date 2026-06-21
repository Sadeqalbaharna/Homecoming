#!/usr/bin/env python3
"""
SSH into Raspberry Pi and run V1 setup

Usage:
    python pi_setup.py 192.168.39.5
"""

import sys
import paramiko
import time

PI_IP = sys.argv[1] if len(sys.argv) > 1 else "192.168.39.5"
PI_USER = "pi"
PI_PASS = "raspberry"  # Change if you've modified default password

# Session 1 setup commands
SETUP_COMMANDS = """
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y python3-dev python3-pip alsa-utils espeak-ng git libopenjp2-7 libtiff5 libjasper1

# Install Python packages
pip3 install firebase-admin openai

# Check audio device
arecord -l

# Create kai directory
mkdir -p /home/pi/kai

echo "✓ Session 1 Complete!"
"""

def run_setup():
    print(f"🔌 Connecting to Pi at {PI_IP}...")
    
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    
    try:
        client.connect(PI_IP, username=PI_USER, password=PI_PASS, timeout=10)
        print(f"✓ Connected to {PI_IP}")
        
        print("\n📦 Running Session 1 setup...\n")
        
        # Run each command
        for cmd in SETUP_COMMANDS.strip().split('\n'):
            if cmd.startswith('#') or not cmd.strip():
                print(f"  {cmd}")
                continue
            
            print(f"  → {cmd}")
            stdin, stdout, stderr = client.exec_command(cmd)
            
            # Wait for command to finish
            exit_status = stdout.channel.recv_exit_status()
            output = stdout.read().decode('utf-8', errors='ignore')
            error = stderr.read().decode('utf-8', errors='ignore')
            
            if output:
                for line in output.split('\n'):
                    if line.strip():
                        print(f"    {line}")
            if error and exit_status != 0:
                print(f"    ⚠️ {error}")
            
            time.sleep(0.5)
        
        print("\n✓ Setup complete!")
        print("Next: Check audio device output above")
        print("       Run Session 2 when ready")
        
        client.close()
        
    except paramiko.AuthenticationException:
        print(f"❌ Auth failed. Check credentials (default: pi/raspberry)")
    except paramiko.SSHException as e:
        print(f"❌ SSH error: {e}")
    except Exception as e:
        print(f"❌ Error: {e}")

if __name__ == "__main__":
    run_setup()
