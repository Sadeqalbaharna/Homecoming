#!/usr/bin/env python3
"""
Interactive Deployment Guide for AI Music Query Generator
Run this on the Pi or follow the instructions manually
"""

import subprocess
import sys

def run_command(cmd, description):
    """Run a command and report status"""
    print(f"\n📍 {description}")
    print(f"   Command: {cmd}")
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if result.returncode == 0:
            print(f"   ✅ Success")
            if result.stdout:
                for line in result.stdout.strip().split('\n')[:5]:
                    print(f"   → {line}")
            return True
        else:
            print(f"   ❌ Failed: {result.stderr}")
            return False
    except Exception as e:
        print(f"   ❌ Error: {e}")
        return False

def main():
    print("\n" + "="*70)
    print("🧠 AI MUSIC QUERY GENERATOR - DEPLOYMENT ASSISTANT")
    print("="*70)
    
    print("\n📦 This will update firebase_rest_listener_debug.py with AI music queries")
    print("\nDeployment steps:")
    print("1. ✅ Backup current listener")
    print("2. ✅ Pull latest code from Git")
    print("3. ✅ Stop running listener")
    print("4. ✅ Restart with new code")
    print("5. ✅ Verify it's working")
    
    input("\nPress Enter to continue...")
    
    # Step 1: Backup
    if not run_command(
        "cp /home/pi/firebase_rest_listener_debug.py /home/pi/firebase_rest_listener_debug.py.backup",
        "Step 1: Backup current listener"
    ):
        print("   ⚠️  Backup might have failed, but continuing...")
    
    # Step 2: Pull from Git
    if not run_command(
        "cd /home/pi && git pull origin main",
        "Step 2: Pull latest code from Git"
    ):
        print("   ❌ Git pull failed. Make sure you're in the repo and have internet.")
        print("   💡 Alternatively, check the deployment guide:")
        print("      AI_MUSIC_DEPLOYMENT_GUIDE.md")
        return False
    
    # Step 3: Stop listener
    print("\n📍 Step 3: Stop running listener")
    run_command("pkill -f firebase_rest_listener_debug", "Stopping listener process")
    
    import time
    time.sleep(2)
    
    # Step 4: Restart listener
    if run_command(
        "cd /home/pi && sudo nohup python3 firebase_rest_listener_debug.py > listener.log 2>&1 &",
        "Step 4: Restart listener with new code"
    ):
        time.sleep(3)
        
        # Step 5: Verify
        print("\n📍 Step 5: Verify listener is running")
        run_command(
            "ps aux | grep firebase_rest_listener_debug | grep -v grep",
            "Checking if listener process started"
        )
        
        # Check for new log entries
        run_command(
            "tail -20 /home/pi/listener.log",
            "Latest listener log entries"
        )
    
    print("\n" + "="*70)
    print("✅ DEPLOYMENT COMPLETE!")
    print("="*70)
    print("\n🧪 Test the new system with:")
    print("""
curl -X POST http://localhost:5001/kai/ambiance \\
  -H "Content-Type: application/json" \\
  -d '{"prompt": "Warm cozy tavern with medieval folk music", "include_music": true}'
    """)
    
    print("\n📊 Monitor music AI in logs with:")
    print("   tail -f /home/pi/listener.log | grep '🧠'")
    
    print("\n📖 For more information, read:")
    print("   - AI_MUSIC_DEPLOYMENT_GUIDE.md")
    print("   - AI_MUSIC_CHANGES.md")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n⚠️  Deployment cancelled by user")
        sys.exit(1)
