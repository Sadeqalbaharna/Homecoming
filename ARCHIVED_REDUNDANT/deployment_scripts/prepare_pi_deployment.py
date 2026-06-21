#!/usr/bin/env python3
"""
Deploy scene test files to Pi via base64 encoding and SSH/scp alternative
"""

import os
import base64
import subprocess
import sys
from pathlib import Path

# Files to deploy
FILES_TO_DEPLOY = [
    "test_bluetooth_tg129c.py",
    "test_modular_scene_playback.py",
    "demo_modular_scenes.py",
    "verify_setup.py",
]

PI_IP = "192.168.48.5"
PI_USER = "pi"
PI_HOME = "/home/pi"

def encode_file_to_base64(filepath):
    """Read file and encode to base64"""
    with open(filepath, 'rb') as f:
        content = f.read()
    return base64.b64encode(content).decode('utf-8')

def create_transfer_script():
    """Create a Python script that can be pasted on the Pi to decode files"""
    
    print("\n" + "="*70)
    print("📤 SCENE TEST DEPLOYMENT - Base64 Transfer Method")
    print("="*70 + "\n")
    
    # Check files exist
    missing = [f for f in FILES_TO_DEPLOY if not Path(f).exists()]
    if missing:
        print(f"❌ Missing files: {missing}")
        return False
    
    print("✅ All files found\n")
    
    # Create receiver script
    receiver_script = "#!/usr/bin/env python3\n"
    receiver_script += "import base64\n\n"
    receiver_script += "# Encoded files - copy this entire script to Pi\n"
    receiver_script += "files = {\n"
    
    for filename in FILES_TO_DEPLOY:
        b64_content = encode_file_to_base64(filename)
        receiver_script += f'    "{filename}": """\n'
        # Break into lines for readability
        for i in range(0, len(b64_content), 76):
            receiver_script += b64_content[i:i+76] + "\n"
        receiver_script += '    """,\n'
    
    receiver_script += """}\n
print("📥 Decoding files...")
for filename, b64_content in files.items():
    content = base64.b64decode(b64_content.encode())
    with open(filename, 'wb') as f:
        f.write(content)
    print(f"   ✅ {filename}")

print("\\n✅ All files deployed!\\n")
print("Run tests with:")
print("  python test_bluetooth_tg129c.py")
print("  python test_modular_scene_playback.py haunted_mansion")
"""
    
    # Save receiver script
    receiver_path = "deploy_receiver.py"
    with open(receiver_path, 'w') as f:
        f.write(receiver_script)
    
    print(f"✅ Created transfer script: {receiver_path}\n")
    print("="*70)
    print("📋 DEPLOYMENT INSTRUCTIONS")
    print("="*70 + "\n")
    
    print("1️⃣  Copy the receiver script to the Pi:")
    print(f"   scp deploy_receiver.py pi@{PI_IP}:/home/pi/\n")
    
    print("2️⃣  SSH into the Pi:")
    print(f"   ssh pi@{PI_IP}\n")
    
    print("3️⃣  Run the receiver script:")
    print("   python deploy_receiver.py\n")
    
    print("4️⃣  Test the deployment:")
    print("   python test_bluetooth_tg129c.py\n")
    
    print("="*70)
    print(f"📦 Total transfer size: ~{len(receiver_script)/1024:.1f} KB\n")
    
    return True

if __name__ == "__main__":
    create_transfer_script()
