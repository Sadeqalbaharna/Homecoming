#!/usr/bin/env python3
"""
Test Kai Consciousness API Connection
Quick diagnostic tool for Flask server connectivity
"""
import requests
import json
import time

PI_IP = "192.168.213.5"
BASE_URL = f"http://{PI_IP}:5001"

def test_connection():
    """Test basic Pi connectivity"""
    print("🔍 Testing Pi Consciousness API Connection...")
    print("=" * 50)
    
    # Test 1: Basic ping
    print(f"📡 Testing connectivity to {PI_IP}...")
    import subprocess
    try:
        result = subprocess.run(["ping", "-n", "1", PI_IP], capture_output=True, text=True)
        if "TTL=" in result.stdout:
            print("✅ Pi is reachable via ping")
        else:
            print("❌ Pi is not responding to ping")
            return False
    except:
        print("❌ Could not ping Pi")
        return False
    
    # Test 2: Status endpoint
    print(f"\n🌐 Testing Flask server at {BASE_URL}/kai/status...")
    try:
        response = requests.get(f"{BASE_URL}/kai/status", timeout=5)
        if response.status_code == 200:
            data = response.json()
            print("✅ Status endpoint working!")
            print(f"   Server status: {data.get('status', 'unknown')}")
            print(f"   LED strips: {len(data.get('led_strips', []))}")
            print(f"   Audio device: {data.get('bluetooth_device', 'unknown')}")
        else:
            print(f"❌ Status endpoint returned {response.status_code}")
            return False
    except requests.exceptions.ConnectionError:
        print("❌ Cannot connect to Flask server - server not running")
        return False
    except requests.exceptions.Timeout:
        print("❌ Connection timeout - server may be overloaded")
        return False
    except Exception as e:
        print(f"❌ Status endpoint error: {e}")
        return False
    
    # Test 3: Context endpoint (like mobile app)
    print(f"\n🤖 Testing context endpoint at {BASE_URL}/kai/context...")
    try:
        test_payload = {
            'user_message': 'Hey Kai, turn on blue lights',
            'timestamp': int(time.time() * 1000)
        }
        
        response = requests.post(
            f"{BASE_URL}/kai/context",
            json=test_payload,
            timeout=10
        )
        
        if response.status_code == 200:
            data = response.json()
            print("✅ Context endpoint working!")
            context = data.get('kai_technical_context', {})
            hardware = context.get('hardware_setup', {})
            print(f"   LED count: {hardware.get('led_count', 0)}")
            print(f"   Brightness: {hardware.get('brightness_level', 0)}%")
            print(f"   Music tracks: {len(context.get('current_state', {}).get('available_tracks', []))}")
        else:
            print(f"❌ Context endpoint returned {response.status_code}")
            print(f"   Response: {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ Context endpoint error: {e}")
        return False
    
    print("\n🎉 ALL TESTS PASSED!")
    print("✅ Kai consciousness system is fully operational")
    print("✅ Mobile app should be able to connect successfully")
    return True

def diagnose_failure():
    """Provide diagnostic information for failures"""
    print("\n🔧 TROUBLESHOOTING STEPS:")
    print("1. Check if Firebase listener is running:")
    print("   ps aux | grep firebase")
    print("\n2. Restart the Firebase listener:")
    print("   cd /home/pi && sudo python3 firebase_rest_listener_debug.py")
    print("\n3. Check if port 5001 is being used:")
    print("   sudo netstat -tulpn | grep 5001")
    print("\n4. Kill any processes on port 5001:")
    print("   sudo fuser -k 5001/tcp")
    print("\n5. Check firewall settings:")
    print("   sudo ufw status")

if __name__ == "__main__":
    if not test_connection():
        diagnose_failure()
    
    print(f"\n🚀 To test from mobile app, it should connect to:")
    print(f"   {BASE_URL}/kai/context")
    print(f"   {BASE_URL}/kai/status")