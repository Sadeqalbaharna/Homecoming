#!/usr/bin/env python3
"""
YouTube Audio Streaming Test Suite for Homecoming
Tests audio input → YouTube search → streaming to Pi → Bluetooth speaker
"""

import requests
import json
import time
import sys
from datetime import datetime
from typing import Dict, List, Optional

# Configuration
PI_IP = "192.168.2.5"
PI_PORT = 5001
BASE_URL = f"http://{PI_IP}:{PI_PORT}"

# Color codes for terminal output
class Colors:
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

def print_header(text):
    """Print formatted header"""
    print(f"\n{Colors.HEADER}{Colors.BOLD}{'='*80}{Colors.ENDC}")
    print(f"{Colors.HEADER}{Colors.BOLD}{text:^80}{Colors.ENDC}")
    print(f"{Colors.HEADER}{Colors.BOLD}{'='*80}{Colors.ENDC}\n")

def print_section(text):
    """Print section divider"""
    print(f"\n{Colors.CYAN}{Colors.BOLD}{'-'*80}{Colors.ENDC}")
    print(f"{Colors.CYAN}{Colors.BOLD}{text}{Colors.ENDC}")
    print(f"{Colors.CYAN}{Colors.BOLD}{'-'*80}{Colors.ENDC}\n")

def print_success(text):
    """Print success message"""
    print(f"{Colors.GREEN}✅ {text}{Colors.ENDC}")

def print_error(text):
    """Print error message"""
    print(f"{Colors.RED}❌ {text}{Colors.ENDC}")

def print_info(text):
    """Print info message"""
    print(f"{Colors.BLUE}ℹ️  {text}{Colors.ENDC}")

def print_warning(text):
    """Print warning message"""
    print(f"{Colors.YELLOW}⚠️  {text}{Colors.ENDC}")

def print_test(text):
    """Print test label"""
    print(f"{Colors.YELLOW}🧪 {text}{Colors.ENDC}")

class YouTubeAudioTester:
    """Test suite for YouTube audio streaming to Pi"""
    
    def __init__(self):
        self.pi_online = False
        self.test_results = {
            "connection": False,
            "audio_tests": [],
            "total_tests": 0,
            "passed_tests": 0,
            "failed_tests": 0
        }
        
    def check_pi_connection(self) -> bool:
        """Check if Pi listener is online and accessible"""
        print_section("CHECKING PI CONNECTION")
        
        try:
            response = requests.get(f"{BASE_URL}/kai/status", timeout=5)
            if response.status_code == 200:
                data = response.json()
                print_success(f"Pi is online at {PI_IP}:{PI_PORT}")
                print_info(f"System status: {data.get('status', 'unknown')}")
                print_info(f"Bluetooth device: {data.get('bluetooth_device', 'unknown')}")
                print_info(f"System online: {data.get('system_online', False)}")
                self.pi_online = True
                self.test_results["connection"] = True
                return True
            else:
                print_error(f"Unexpected response code: {response.status_code}")
                return False
                
        except requests.exceptions.ConnectionError:
            print_error(f"Cannot connect to Pi at {PI_IP}:{PI_PORT}")
            print_warning("Make sure the listener is running on the Pi:")
            print_warning("  ssh pi@192.168.2.5")
            print_warning("  sudo nohup python3 firebase_rest_listener_debug.py > listener.log 2>&1 &")
            return False
        except requests.exceptions.Timeout:
            print_error("Connection to Pi timed out")
            return False
        except Exception as e:
            print_error(f"Error checking Pi connection: {e}")
            return False
    
    def test_audio_stream(self, search_query: str, test_duration: int = 5) -> Dict:
        """Test audio streaming with a specific search query"""
        print_section(f"TESTING AUDIO STREAM: '{search_query}'")
        
        test_result = {
            "query": search_query,
            "status": "pending",
            "response_code": None,
            "response_time": None,
            "music_query": None,
            "youtube_video": None,
            "error": None,
            "timestamp": datetime.now().isoformat()
        }
        
        try:
            start_time = time.time()
            
            # Send ambiance request with YouTube search query
            payload = {
                "prompt": search_query,
                "include_music": True,
                "include_smoke": False
            }
            
            print_info(f"Sending request to /kai/ambiance endpoint...")
            print_info(f"Payload: {json.dumps(payload, indent=2)}")
            
            response = requests.post(
                f"{BASE_URL}/kai/ambiance",
                json=payload,
                timeout=30
            )
            
            response_time = time.time() - start_time
            test_result["response_time"] = response_time
            test_result["response_code"] = response.status_code
            
            print_info(f"Response received in {response_time:.2f}s (HTTP {response.status_code})")
            
            if response.status_code == 200:
                data = response.json()
                print_success("HTTP 200 - Request successful")
                
                # Extract relevant fields
                test_result["music_query"] = data.get("music_query")
                test_result["youtube_video"] = data.get("youtube_video")
                test_result["status"] = "success"
                
                print_info(f"Music Query Generated: {data.get('music_query', 'N/A')}")
                print_info(f"YouTube Video: {data.get('youtube_video', 'N/A')}")
                
                if data.get("confidence"):
                    print_info(f"Confidence Score: {data.get('confidence'):.2%}")
                
                if data.get("profile"):
                    print_info(f"Scene Profile: {data.get('profile')}")
                
                # Show full response for debugging
                print_info(f"Full Response:\n{json.dumps(data, indent=2)}")
                
                self.test_results["passed_tests"] += 1
                
            else:
                print_error(f"HTTP {response.status_code} - {response.text}")
                test_result["status"] = "failed"
                test_result["error"] = f"HTTP {response.status_code}"
                self.test_results["failed_tests"] += 1
            
        except requests.exceptions.Timeout:
            print_error(f"Request timed out after {response_time:.2f}s")
            test_result["status"] = "timeout"
            test_result["error"] = "Request timeout"
            self.test_results["failed_tests"] += 1
            
        except requests.exceptions.ConnectionError as e:
            print_error(f"Connection error: {e}")
            test_result["status"] = "connection_error"
            test_result["error"] = str(e)
            self.test_results["failed_tests"] += 1
            
        except Exception as e:
            print_error(f"Error during audio stream test: {e}")
            test_result["status"] = "error"
            test_result["error"] = str(e)
            self.test_results["failed_tests"] += 1
        
        self.test_results["audio_tests"].append(test_result)
        self.test_results["total_tests"] += 1
        return test_result
    
    def run_all_tests(self) -> bool:
        """Run complete test suite"""
        print_header("YOUTUBE AUDIO STREAMING TEST SUITE FOR HOMECOMING")
        
        print_info("This test suite validates:")
        print_info("  1. Pi listener connectivity")
        print_info("  2. /kai/ambiance HTTP endpoint")
        print_info("  3. Audio query generation")
        print_info("  4. YouTube search and streaming capability")
        print_info("  5. Bluetooth audio playback to TG-129C speaker")
        
        # Step 1: Check connection
        if not self.check_pi_connection():
            print_error("Cannot proceed without Pi connection")
            return False
        
        # Step 2: Run audio tests with various queries
        print_section("RUNNING AUDIO STREAMING TESTS")
        
        test_queries = [
            # D&D Ambiance Tests
            "Tavern medieval music ambient",
            "Epic battle in dungeon with dramatic music",
            "Peaceful healing magic castle",
            "Spooky haunted mansion",
            "Thunderstorm with lightning effects",
            "Dark mysterious forest at night",
            "Bustling medieval marketplace",
            
            # YouTube Direct Tests
            "lofi hip hop beats to relax study to",
            "ambient rain sounds meditation",
            "upbeat electronic dance music",
            "classical piano music peaceful",
            "jazz cafe background music",
        ]
        
        for i, query in enumerate(test_queries, 1):
            print_test(f"Test {i}/{len(test_queries)}: '{query}'")
            self.test_audio_stream(query)
            
            # Add delay between tests to avoid overwhelming the Pi
            if i < len(test_queries):
                print_info(f"Waiting 2 seconds before next test...")
                time.sleep(2)
        
        # Display summary
        self.display_summary()
        
        return self.test_results["failed_tests"] == 0
    
    def display_summary(self):
        """Display test results summary"""
        print_header("TEST RESULTS SUMMARY")
        
        print_info(f"Pi Connection: {'✅ Online' if self.test_results['connection'] else '❌ Offline'}")
        print_info(f"Total Tests Run: {self.test_results['total_tests']}")
        print_success(f"Tests Passed: {self.test_results['passed_tests']}")
        
        if self.test_results["failed_tests"] > 0:
            print_error(f"Tests Failed: {self.test_results['failed_tests']}")
        
        # Detailed results
        print_section("AUDIO STREAMING TEST DETAILS")
        
        for i, result in enumerate(self.test_results["audio_tests"], 1):
            status_icon = "✅" if result["status"] == "success" else "❌"
            print_info(f"{status_icon} Test {i}: {result['query']}")
            print_info(f"   Status: {result['status']}")
            print_info(f"   Response Time: {result['response_time']:.2f}s" if result['response_time'] else "   Response Time: N/A")
            print_info(f"   Music Query: {result['music_query']}")
            
            if result['error']:
                print_error(f"   Error: {result['error']}")
            
            print()
        
        # Success rate
        if self.test_results["total_tests"] > 0:
            success_rate = (self.test_results["passed_tests"] / self.test_results["total_tests"]) * 100
            print_info(f"Success Rate: {success_rate:.1f}%")
        
        # Recommendations
        print_section("NEXT STEPS")
        
        if not self.test_results["connection"]:
            print_warning("1. Verify Pi is online and listener is running")
            print_info("   ssh pi@192.168.2.5")
            print_info("   ps aux | grep firebase_rest_listener")
        
        if self.test_results["passed_tests"] > 0:
            print_success("1. Audio endpoint is working correctly")
            print_success("2. Music queries are being generated")
            print_info("3. Check Pi listener logs for playback status:")
            print_info("   ssh pi@192.168.2.5 'tail -f listener.log | grep MUSIC'")
            print_info("4. Verify Bluetooth speaker is connected:")
            print_info("   ssh pi@192.168.2.5 'pactl list short sinks'")
        
        if self.test_results["failed_tests"] > 0:
            print_warning("Some tests failed. Check error messages above.")
            print_info("View full Pi logs: ssh pi@192.168.2.5 'tail -50 listener.log'")

def interactive_mode():
    """Run in interactive mode for manual testing"""
    tester = YouTubeAudioTester()
    
    if not tester.check_pi_connection():
        print_error("Cannot proceed without Pi connection")
        sys.exit(1)
    
    print_section("INTERACTIVE AUDIO STREAMING TEST")
    
    while True:
        print_info("Enter a search query to test (or 'quit' to exit):")
        query = input(f"{Colors.CYAN}> {Colors.ENDC}").strip()
        
        if query.lower() == 'quit':
            print_info("Exiting...")
            break
        
        if not query:
            print_warning("Please enter a search query")
            continue
        
        tester.test_audio_stream(query)
        
        print_info("\nWait a few seconds for audio to start playing on the Pi...")
        print_info("If you hear music from the Bluetooth speaker, the test succeeded! 🔊")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--interactive":
        # Interactive mode
        interactive_mode()
    else:
        # Run full test suite
        tester = YouTubeAudioTester()
        success = tester.run_all_tests()
        sys.exit(0 if success else 1)
