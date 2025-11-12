#!/usr/bin/env python3
"""
Deploy WS2812B setup and test files to Raspberry Pi
Homecoming LED Hardware Deployment Script
"""

import os
import subprocess
import sys
from pathlib import Path

# Pi connection details
PI_IP = "192.168.213.5"
PI_USER = "pi"
PI_HOME = f"/home/{PI_USER}"

def run_command(cmd, description):
    """Run command with logging"""
    print(f"🔧 {description}...")
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if result.returncode == 0:
            print(f"   ✅ {description} completed")
            if result.stdout.strip():
                print(f"   Output: {result.stdout.strip()}")
        else:
            print(f"   ❌ {description} failed: {result.stderr.strip()}")
            return False
    except Exception as e:
        print(f"   ❌ {description} error: {e}")
        return False
    return True

def deploy_files():
    """Deploy LED setup files to Pi"""
    print("🚀 Deploying WS2812B files to Pi...")
    
    files_to_deploy = [
        "firebase_rest_listener_debug.py",
        "test_led_hardware.py", 
        "WS2812B_WIRING_GUIDE.md"
    ]
    
    # Check files exist
    for file in files_to_deploy:
        if not os.path.exists(file):
            print(f"❌ File not found: {file}")
            return False
    
    # Deploy each file
    for file in files_to_deploy:
        cmd = f'scp "{file}" {PI_USER}@{PI_IP}:{PI_HOME}/'
        if not run_command(cmd, f"Uploading {file}"):
            return False
    
    return True

def install_dependencies():
    """Install required Python packages on Pi"""
    print("📦 Installing dependencies on Pi...")
    
    dependencies = [
        "rpi_ws281x",
        "flask", 
        "flask-cors",
        "requests",
        "adafruit-circuitpython-neopixel"
    ]
    
    for dep in dependencies:
        cmd = f'ssh {PI_USER}@{PI_IP} "sudo pip3 install {dep}"'
        run_command(cmd, f"Installing {dep}")

def set_permissions():
    """Set proper permissions for scripts"""
    print("🔐 Setting file permissions...")
    
    commands = [
        f'ssh {PI_USER}@{PI_IP} "chmod +x {PI_HOME}/test_led_hardware.py"',
        f'ssh {PI_USER}@{PI_IP} "chmod +x {PI_HOME}/firebase_rest_listener_debug.py"'
    ]
    
    for cmd in commands:
        run_command(cmd, "Setting execute permissions")

def test_connection():
    """Test SSH connection to Pi"""
    print("🔍 Testing connection to Pi...")
    cmd = f'ssh -o ConnectTimeout=5 {PI_USER}@{PI_IP} "echo \'Pi connection successful\'"'
    return run_command(cmd, "Testing SSH connection")

def run_hardware_test():
    """Run hardware test on Pi"""
    print("🧪 Running LED hardware test on Pi...")
    cmd = f'ssh {PI_USER}@{PI_IP} "cd {PI_HOME} && python3 test_led_hardware.py"'
    run_command(cmd, "Running hardware test")

def main():
    print("🏡 Homecoming WS2812B Deployment Script")
    print("=" * 50)
    print(f"Target Pi: {PI_IP}")
    print(f"User: {PI_USER}")
    print()
    
    # Test connection first
    if not test_connection():
        print("❌ Cannot connect to Pi. Check:")
        print("   - Pi IP address is correct")
        print("   - SSH is enabled on Pi")
        print("   - Network connectivity")
        return False
    
    # Deploy files
    if not deploy_files():
        print("❌ File deployment failed")
        return False
    
    # Install dependencies
    install_dependencies()
    
    # Set permissions
    set_permissions()
    
    print("\n✅ Deployment completed!")
    print()
    print("🔧 Next Steps:")
    print("1. Connect your WS2812B strips according to WS2812B_WIRING_GUIDE.md")
    print("2. SSH to Pi and run: python3 test_led_hardware.py")
    print("3. If tests pass, start the main service: python3 firebase_rest_listener_debug.py")
    print()
    print("📋 Hardware Test Commands:")
    print(f"   ssh {PI_USER}@{PI_IP}")
    print("   python3 test_led_hardware.py")
    
    # Ask if user wants to run test now
    try:
        response = input("\n🤔 Run hardware test now? (y/N): ").strip().lower()
        if response in ['y', 'yes']:
            run_hardware_test()
    except KeyboardInterrupt:
        print("\n👋 Deployment complete!")
    
    return True

if __name__ == "__main__":
    try:
        success = main()
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n⏹️  Deployment cancelled by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Deployment failed: {e}")
        sys.exit(1)