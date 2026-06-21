#!/usr/bin/env python3
"""
Interactive Test Suite for AI Music Query Generator
Tests all D&D scenes via HTTP endpoint
"""

import requests
import json
import time
from datetime import datetime

BASE_URL = "http://192.168.2.5:5001"
AMBIANCE_ENDPOINT = f"{BASE_URL}/kai/ambiance"
STATUS_ENDPOINT = f"{BASE_URL}/kai/status"

# Color codes for terminal output
class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

def print_header(text):
    print(f"\n{Colors.HEADER}{Colors.BOLD}{'='*70}{Colors.ENDC}")
    print(f"{Colors.HEADER}{Colors.BOLD}{text:^70}{Colors.ENDC}")
    print(f"{Colors.HEADER}{Colors.BOLD}{'='*70}{Colors.ENDC}\n")

def print_success(text):
    print(f"{Colors.OKGREEN}✅ {text}{Colors.ENDC}")

def print_error(text):
    print(f"{Colors.FAIL}❌ {text}{Colors.ENDC}")

def print_info(text):
    print(f"{Colors.OKCYAN}ℹ️ {text}{Colors.ENDC}")

def print_test(text):
    print(f"{Colors.WARNING}🧪 {text}{Colors.ENDC}")

def check_listener_status():
    """Check if the Pi listener is running and healthy"""
    print_header("CHECKING LISTENER STATUS")
    
    try:
        response = requests.get(STATUS_ENDPOINT, timeout=5)
        if response.status_code == 200:
            data = response.json()
            print_success(f"Listener is ONLINE")
            print(f"  System Status: {data.get('system_online')}")
            print(f"  LED Strips: {data.get('led_strips')}")
            print(f"  Bluetooth Device: {data.get('bluetooth_device')}")
            print(f"  Consciousness Level: {data.get('consciousness_level')}")
            return True
        else:
            print_error(f"Unexpected status code: {response.status_code}")
            return False
    except requests.exceptions.ConnectionError:
        print_error("Cannot connect to Pi listener (connection refused)")
        return False
    except requests.exceptions.Timeout:
        print_error("Connection timeout - Pi may be offline")
        return False
    except Exception as e:
        print_error(f"Error checking status: {e}")
        return False

def test_ambiance_scene(name, prompt, include_music=True, include_smoke=False):
    """Test a single ambiance scene"""
    print(f"\n{Colors.OKBLUE}🎭 Testing: {name}{Colors.ENDC}")
    print(f"   Prompt: {prompt}")
    print(f"   Music: {'✅' if include_music else '❌'}, Smoke: {'✅' if include_smoke else '❌'}")
    
    payload = {
        "prompt": prompt,
        "include_music": include_music,
        "include_smoke": include_smoke
    }
    
    try:
        response = requests.post(
            AMBIANCE_ENDPOINT,
            json=payload,
            timeout=10
        )
        
        if response.status_code == 200:
            data = response.json()
            
            if data.get('success'):
                print_success(f"Scene loaded: {data.get('scene_name')}")
                print(f"   Description: {data.get('description')}")
                print(f"   Music Query: {Colors.BOLD}{data.get('music_query')}{Colors.ENDC}")
                print(f"   Lighting: {'✅' if data.get('lighting_applied') else '❌'}")
                print(f"   Music: {'✅' if data.get('music_applied') else '❌'}")
                print(f"   Confidence: {data.get('confidence', 0):.1%}")
                
                # Check if this is the new AI system
                if data.get('music_query'):
                    print(f"   {Colors.OKGREEN}[AI MUSIC SYSTEM ACTIVE]{Colors.ENDC}")
                
                return True
            else:
                print_error(f"Scene failed: {data.get('error', 'Unknown error')}")
                return False
        else:
            print_error(f"HTTP {response.status_code}: {response.text}")
            return False
            
    except requests.exceptions.Timeout:
        print_error("Request timeout - scene processing took too long")
        return False
    except Exception as e:
        print_error(f"Exception: {e}")
        return False

def run_full_test_suite():
    """Run tests on all D&D scenes"""
    print_header("AI MUSIC QUERY GENERATOR - FULL TEST SUITE")
    
    # Check listener status
    if not check_listener_status():
        print_error("Cannot proceed - listener is not responding")
        print_info("Deploy the updated listener first:")
        print("  ssh pi@192.168.2.5")
        print("  cd /home/pi && git pull origin main")
        print("  pkill -f firebase_rest_listener_debug")
        print("  sudo nohup python3 firebase_rest_listener_debug.py > listener.log 2>&1 &")
        return
    
    # Test scenarios
    test_cases = [
        {
            "name": "Tavern Scene",
            "prompt": "Warm cozy tavern with medieval folk music and hearty ale",
            "music": True
        },
        {
            "name": "Haunted Mansion",
            "prompt": "Creepy haunted mansion filled with ghostly whispers and eerie atmosphere",
            "music": True
        },
        {
            "name": "Epic Battle",
            "prompt": "Intense epic battle in the dark dungeon with dramatic combat music",
            "music": True
        },
        {
            "name": "Peaceful Healing",
            "prompt": "Peaceful healing magic in the castle with serene music",
            "music": True
        },
        {
            "name": "Thunderstorm",
            "prompt": "Intense thunderstorm with lightning bolts and dramatic thunder sounds",
            "music": True
        },
        {
            "name": "Forest Scene",
            "prompt": "Dark mysterious forest at night with ancient trees",
            "music": True
        },
        {
            "name": "Market Square",
            "prompt": "Bustling medieval marketplace with merchants and traders",
            "music": True
        },
    ]
    
    results = []
    print_header("RUNNING TEST SUITE")
    
    for i, test in enumerate(test_cases, 1):
        print(f"\n{Colors.BOLD}[{i}/{len(test_cases)}]{Colors.ENDC}")
        success = test_ambiance_scene(
            test["name"],
            test["prompt"],
            include_music=test["music"]
        )
        results.append((test["name"], success))
        time.sleep(1)  # Brief pause between tests
    
    # Summary
    print_header("TEST RESULTS SUMMARY")
    
    passed = sum(1 for _, success in results if success)
    total = len(results)
    
    for name, success in results:
        status = f"{Colors.OKGREEN}✅ PASS{Colors.ENDC}" if success else f"{Colors.FAIL}❌ FAIL{Colors.ENDC}"
        print(f"  {name:<25} {status}")
    
    print(f"\n{Colors.BOLD}Total: {passed}/{total} tests passed{Colors.ENDC}")
    
    if passed == total:
        print_success("ALL TESTS PASSED! 🎉")
        print_info("AI Music System is working perfectly!")
    elif passed > 0:
        print_error(f"{total - passed} test(s) failed - check Pi logs")
        print_info("Run: tail -f /home/pi/listener.log | grep 'MUSIC AI'")
    else:
        print_error("All tests failed - listener may have issues")

if __name__ == "__main__":
    try:
        run_full_test_suite()
    except KeyboardInterrupt:
        print(f"\n{Colors.WARNING}Tests interrupted by user{Colors.ENDC}")
    except Exception as e:
        print_error(f"Unexpected error: {e}")
        import traceback
        traceback.print_exc()
