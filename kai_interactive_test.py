#!/usr/bin/env python3
"""
Interactive Kai YouTube Search & Play Test
Type prompts and Kai will search YouTube and stream audio
"""

import requests
import json
import sys
import time
from datetime import datetime

PI_IP = "192.168.2.5"
PI_PORT = 5001
BASE_URL = f"http://{PI_IP}:{PI_PORT}"

class Colors:
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BLUE = '\033[94m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

def print_header():
    print(f"\n{Colors.BLUE}{Colors.BOLD}{'='*80}{Colors.ENDC}")
    print(f"{Colors.BLUE}{Colors.BOLD}KAI INTERACTIVE YOUTUBE SEARCH & PLAY TEST{Colors.ENDC}")
    print(f"{Colors.BLUE}{Colors.BOLD}{'='*80}{Colors.ENDC}\n")

def print_info(text):
    print(f"{Colors.CYAN}ℹ️  {text}{Colors.ENDC}")

def print_success(text):
    print(f"{Colors.GREEN}✅ {text}{Colors.ENDC}")

def print_error(text):
    print(f"{Colors.RED}❌ {text}{Colors.ENDC}")

def print_prompt():
    print(f"\n{Colors.YELLOW}{Colors.BOLD}Enter your prompt:{Colors.ENDC}")
    print(f"{Colors.YELLOW}(or 'quit' to exit, 'help' for examples){Colors.ENDC}")

def check_pi_connection():
    """Verify Pi is online"""
    try:
        response = requests.get(f"{BASE_URL}/kai/status", timeout=5)
        if response.status_code == 200:
            print_success(f"Connected to Pi at {PI_IP}:{PI_PORT}")
            return True
    except:
        pass
    return False

def send_prompt_to_kai(prompt):
    """Send prompt to Kai and get YouTube search result"""
    if not prompt.strip():
        print_error("Prompt cannot be empty")
        return False
    
    payload = {
        "prompt": prompt,
        "include_music": True,
        "include_smoke": False
    }
    
    print_info(f"Sending to Kai: '{prompt}'")
    print_info("⏳ Searching YouTube and starting playback...")
    
    try:
        start_time = time.time()
        response = requests.post(
            f"{BASE_URL}/kai/ambiance",
            json=payload,
            timeout=60
        )
        elapsed = time.time() - start_time
        
        if response.status_code == 200:
            data = response.json()
            
            print_success(f"Response received in {elapsed:.1f}s")
            print(f"\n{Colors.BOLD}SCENE ANALYSIS:{Colors.ENDC}")
            print(f"  Scene: {data.get('scene_name', 'Unknown')}")
            print(f"  Profile: {data.get('profile', 'N/A')}")
            print(f"  Confidence: {data.get('confidence', 0):.0%}")
            
            print(f"\n{Colors.BOLD}MUSIC DETAILS:{Colors.ENDC}")
            print(f"  Generated Query: {data.get('music_query', 'N/A')}")
            print(f"  YouTube Video: {data.get('youtube_video', 'N/A')}")
            print(f"  Status: {'Playing' if data.get('music_applied') else 'Failed to play'}")
            
            print(f"\n{Colors.BOLD}LIGHTING:{Colors.ENDC}")
            print(f"  Lights Applied: {'Yes' if data.get('lighting_applied') else 'No'}")
            
            if data.get('music_applied'):
                print_success("🔊 Audio should now be playing on your Bluetooth speaker!")
                print_info("Listen for music from your TG-129C speaker...")
                return True
            else:
                print_error("Music playback failed - check Pi logs")
                return False
        else:
            print_error(f"HTTP {response.status_code}: {response.text}")
            return False
            
    except requests.exceptions.Timeout:
        print_error(f"Request timed out after {elapsed:.1f}s")
        print_info("(YouTube search or video download may be slow)")
        return False
    except requests.exceptions.ConnectionError:
        print_error(f"Cannot connect to Pi at {PI_IP}:{PI_PORT}")
        return False
    except Exception as e:
        print_error(f"Error: {e}")
        return False

def show_examples():
    """Show example prompts"""
    print(f"\n{Colors.BOLD}EXAMPLE PROMPTS:{Colors.ENDC}\n")
    
    examples = [
        ("D&D Ambiance", [
            "Tavern medieval music ambient",
            "Epic battle in dungeon",
            "Haunted mansion spooky",
            "Peaceful healing magic castle",
            "Thunderstorm with lightning",
            "Dark mysterious forest",
            "Bustling medieval marketplace"
        ]),
        ("YouTube Direct Search", [
            "lofi hip hop beats to relax",
            "ambient rain sounds meditation",
            "jazz cafe background music",
            "classical piano relaxing",
            "upbeat electronic dance music",
            "nature sounds forest birds",
            "ocean waves relaxation"
        ]),
        ("Custom", [
            "Any text you want - Kai will analyze and find music!",
            "Type anything and see what Kai recommends",
            "The more descriptive, the better the results"
        ])
    ]
    
    for category, prompts in examples:
        print(f"{Colors.YELLOW}{Colors.BOLD}{category}:{Colors.ENDC}")
        for prompt in prompts:
            print(f"  • {prompt}")
        print()

def main():
    print_header()
    
    # Check Pi connection
    print_info("Checking connection to Pi...")
    if not check_pi_connection():
        print_error("Cannot connect to Pi at {PI_IP}:{PI_PORT}")
        print_info("Make sure the listener is running:")
        print_info("  ssh pi@192.168.2.5")
        print_info("  sudo nohup python3 firebase_rest_listener_debug.py > listener.log 2>&1 &")
        sys.exit(1)
    
    print_info("📍 Listening on: /kai/ambiance endpoint")
    print_info("🎧 Audio output: Bluetooth speaker (TG-129C)")
    print_info("💡 Also controls LED lighting based on scene")
    
    # Show help
    show_examples()
    
    # Interactive loop
    while True:
        print_prompt()
        
        try:
            user_input = input(f"{Colors.CYAN}> {Colors.ENDC}").strip()
        except (KeyboardInterrupt, EOFError):
            print(f"\n{Colors.BLUE}Goodbye! 👋{Colors.ENDC}\n")
            sys.exit(0)
        
        if not user_input:
            continue
        
        if user_input.lower() == 'quit':
            print(f"\n{Colors.BLUE}Goodbye! 👋{Colors.ENDC}\n")
            sys.exit(0)
        
        if user_input.lower() == 'help':
            show_examples()
            continue
        
        # Send to Kai
        success = send_prompt_to_kai(user_input)
        
        if success:
            print_info("\n⏳ Waiting 3 seconds before next prompt...")
            time.sleep(3)
        else:
            print_info("Try again with a different prompt")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n{Colors.BLUE}Interrupted by user 👋{Colors.ENDC}\n")
        sys.exit(0)
