#!/usr/bin/env python3
"""
Firebase Database Structure Analyzer - REST API version
Uses Firebase REST API to inspect database without SDK issues
"""

import json
import requests
from pathlib import Path

print("\n" + "="*60)
print("📊 FIREBASE DATABASE STRUCTURE (REST API)")
print("="*60 + "\n")

# Get Firebase credentials to extract project ID
FIREBASE_KEY = Path("c:/Users/sadeq/Downloads/homecoming-74f73-firebase-adminsdk-fbsvc-257ed0f4bd.json")

if not FIREBASE_KEY.exists():
    print("❌ Firebase credentials not found")
    exit(1)

with open(FIREBASE_KEY) as f:
    creds = json.load(f)
    project_id = creds.get("project_id")

print(f"✓ Project ID: {project_id}")
print(f"✓ Database: homecoming-kai-default-rtdb\n")

# Firebase REST API endpoint
database_url = "https://homecoming-kai-default-rtdb.firebaseio.com"

try:
    # Get all data
    response = requests.get(f"{database_url}/.json", timeout=10)
    
    if response.status_code == 200:
        data = response.json()
        
        if data is None:
            print("📭 Database is empty (no data)")
        else:
            print("📊 DATABASE CONTENT:\n")
            print(json.dumps(data, indent=2))
    else:
        print(f"❌ Error: {response.status_code}")
        print(f"   {response.text[:200]}")
        
except requests.exceptions.Timeout:
    print("❌ Connection timeout - Firebase might not be accessible")
except Exception as e:
    print(f"❌ Error: {e}")

print("\n" + "="*60)
