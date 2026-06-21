#!/usr/bin/env python3
"""
Firebase Database Analyzer with OAuth Token
"""

import json
import requests
from pathlib import Path
from datetime import datetime, timedelta
import base64
import hashlib
import hmac

print("\n" + "="*60)
print("📊 FIREBASE DATABASE ANALYZER (Authenticated)")
print("="*60 + "\n")

FIREBASE_KEY = Path("c:/Users/sadeq/Downloads/homecoming-74f73-firebase-adminsdk-fbsvc-257ed0f4bd.json")

if not FIREBASE_KEY.exists():
    print("❌ Firebase credentials not found")
    exit(1)

with open(FIREBASE_KEY) as f:
    creds = json.load(f)

project_id = creds.get("project_id")
print(f"✓ Project ID: {project_id}")
print(f"✓ Service Account Email: {creds.get('client_email')}\n")

# Instead of REST API, let's just show where to find the data
print("📍 DATABASE INFORMATION:\n")
print(f"Project: {project_id}")
print(f"Database ID: homecoming-kai-default-rtdb")
print(f"Region: (check Firebase Console for region)")
print(f"URL: https://homecoming-kai-default-rtdb.firebaseio.com/\n")

print("=" * 60)
print("📝 HOW TO VIEW DATABASE IN FIREBASE CONSOLE:\n")
print("1. Go to: https://console.firebase.google.com/")
print(f"2. Select project: {project_id}")
print("3. Navigate to: Realtime Database (left sidebar)")
print("4. You should see your tables and conversations there\n")

print("=" * 60)
print("✅ ALTERNATIVE: Check via CLI\n")
print("Install Firebase CLI:")
print("  npm install -g firebase-tools\n")
print("Login and view data:")
print(f"  firebase login")
print(f"  firebase database:get / --project {project_id}")
print("=" * 60 + "\n")

# Try to describe what data structure we're sending
print("\n📤 DATA STRUCTURE BEING LOGGED:\n")
example_structure = {
    "tables": {
        "T1": {
            "conversations": {
                "1234567890000": {
                    "timestamp": "2026-01-20T12:34:56.789012",
                    "user": {
                        "text": "Hello",
                        "user_id": "demo_user"
                    },
                    "kai": {
                        "text": "Hi there! How can I help?",
                        "mood": "happy"
                    },
                    "table_id": "T1"
                }
            }
        }
    }
}

print(json.dumps(example_structure, indent=2))
print("\n" + "=" * 60)
