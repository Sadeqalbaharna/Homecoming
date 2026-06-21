#!/usr/bin/env python3
"""Test the /kai/ambiance endpoint"""
import requests
import json

# Pi IP address
PI_IP = "192.168.179.5"
PORT = 5001

def test_ambiance(prompt):
    """Test the ambiance endpoint with a D&D prompt"""
    url = f"http://{PI_IP}:{PORT}/kai/ambiance"
    
    payload = {
        "prompt": prompt,
        "user_id": "test_user"
    }
    
    print(f"🎭 Testing ambiance endpoint...")
    print(f"📍 URL: {url}")
    print(f"📦 Payload: {json.dumps(payload, indent=2)}")
    print()
    
    try:
        response = requests.post(url, json=payload, timeout=10)
        print(f"✅ Status: {response.status_code}")
        print(f"📄 Response: {json.dumps(response.json(), indent=2)}")
        return response.json()
    except Exception as e:
        print(f"❌ Error: {e}")
        return None

if __name__ == "__main__":
    # Test different D&D scenarios
    test_cases = [
        "cast fireball",
        "entering a spooky dungeon",
        "tavern scene",
        "lightning strike",
        "healing spell"
    ]
    
    for prompt in test_cases:
        print(f"\n{'='*60}")
        print(f"Testing: {prompt}")
        print(f"{'='*60}")
        result = test_ambiance(prompt)
        input("\nPress Enter to continue to next test...")
