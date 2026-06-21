#!/usr/bin/env python3
"""
Firebase Realtime Database Analyzer - OAuth Authenticated
Reads actual database content and analyzes structure
"""

import json
import requests
import time
from pathlib import Path
from datetime import datetime, timedelta
import base64
import hmac
import hashlib

print("\n" + "="*70)
print("📊 FIREBASE REALTIME DATABASE ANALYZER")
print("="*70 + "\n")

# Load credentials
FIREBASE_KEY = Path("c:/Users/sadeq/Downloads/homecoming-74f73-firebase-adminsdk-fbsvc-257ed0f4bd.json")

if not FIREBASE_KEY.exists():
    print("❌ Firebase credentials not found")
    exit(1)

with open(FIREBASE_KEY) as f:
    creds = json.load(f)

project_id = creds.get("project_id")
print(f"✓ Project: {project_id}")
print(f"✓ Service Account: {creds.get('client_email')}\n")

# Generate JWT token for OAuth
def create_jwt(service_account_json, scope):
    """Create a signed JWT for Firebase Auth"""
    import jwt as pyjwt
    
    now = int(time.time())
    expiry = now + 3600
    
    payload = {
        'iss': service_account_json['client_email'],
        'scope': scope,
        'aud': 'https://oauth2.googleapis.com/token',
        'exp': expiry,
        'iat': now,
    }
    
    token = pyjwt.encode(
        payload,
        service_account_json['private_key'],
        algorithm='RS256'
    )
    return token

def get_access_token(service_account_json):
    """Exchange JWT for access token"""
    try:
        import jwt as pyjwt
    except ImportError:
        print("⚠️  PyJWT not installed, trying alternative method...\n")
        return None
    
    scope = 'https://www.googleapis.com/auth/firebase.database https://www.googleapis.com/auth/userinfo.email'
    
    jwt_token = create_jwt(service_account_json, scope)
    
    response = requests.post(
        'https://oauth2.googleapis.com/token',
        data={
            'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion': jwt_token,
        }
    )
    
    if response.status_code == 200:
        return response.json().get('access_token')
    else:
        print(f"❌ Token request failed: {response.status_code}")
        print(f"   {response.text}\n")
        return None

# Try to get access token
print("[1/3] Getting access token...")
try:
    access_token = get_access_token(creds)
    if access_token:
        print(f"✓ Access token obtained ({len(access_token)} chars)\n")
    else:
        print("⚠️  Could not get access token, trying unauthenticated access...\n")
        access_token = None
except Exception as e:
    print(f"⚠️  Error getting token: {e}\n")
    print("Attempting without authentication...\n")
    access_token = None

# Read database
print("[2/3] Reading Firebase Realtime Database...")
database_url = "https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app"
headers = {}
if access_token:
    headers['Authorization'] = f'Bearer {access_token}'

try:
    response = requests.get(f"{database_url}/.json", headers=headers, timeout=10)
    
    if response.status_code == 200:
        data = response.json()
        print("✓ Successfully read database\n")
        
        # Analyze structure
        print("[3/3] Analyzing Database Structure...\n")
        print("="*70)
        
        if data is None:
            print("\n📭 DATABASE IS EMPTY")
            print("\nNo data has been written to the database yet.")
            print("\nExpected structure when data is logged:")
            print(json.dumps({
                "tables": {
                    "T1": {
                        "conversations": {
                            "1705766496000": {
                                "timestamp": "2026-01-20T...",
                                "user": {"text": "...", "user_id": "..."},
                                "kai": {"text": "...", "mood": "..."},
                                "table_id": "T1"
                            }
                        }
                    }
                }
            }, indent=2))
        else:
            print("\n📊 DATABASE CONTENT:\n")
            print(json.dumps(data, indent=2))
            
            # Deep analysis
            print("\n" + "="*70)
            print("📈 STRUCTURE ANALYSIS:\n")
            
            def analyze_structure(obj, path=""):
                stats = {
                    "tables": 0,
                    "conversations": 0,
                    "total_entries": 0,
                    "paths": []
                }
                
                if isinstance(obj, dict):
                    for key, value in obj.items():
                        current_path = f"{path}/{key}" if path else key
                        
                        if key == "tables" and isinstance(value, dict):
                            stats["tables"] = len(value)
                            for table_id, table_data in value.items():
                                if isinstance(table_data, dict) and "conversations" in table_data:
                                    convos = table_data["conversations"]
                                    if isinstance(convos, dict):
                                        stats["conversations"] += len(convos)
                        
                        stats["total_entries"] += 1
                        stats["paths"].append(current_path)
                        
                        if isinstance(value, dict):
                            sub_stats = analyze_structure(value, current_path)
                            stats["total_entries"] += sub_stats["total_entries"]
                
                return stats
            
            analysis = analyze_structure(data)
            
            print(f"Total Root Keys: {len(data)}")
            print(f"Tables Found: {analysis['tables']}")
            print(f"Total Conversations: {analysis['conversations']}")
            print(f"Total Keys (recursive): {analysis['total_entries']}")
            
            print(f"\nPaths:")
            for path in analysis["paths"]:
                print(f"  • {path}")
            
            # Show data sizes
            print(f"\nDatabase Size: {len(json.dumps(data))} bytes")
            
    elif response.status_code == 401:
        print("❌ Unauthorized (401)")
        print("The database might have security rules preventing read access.")
        print("\nTo enable public read access for testing:")
        print("1. Go to: https://console.firebase.google.com/")
        print("2. Select project: homecoming-74f73")
        print("3. Realtime Database → Rules")
        print('4. Set both read/write to true: {"rules": {".read": true, ".write": true}}')
        print("5. Try again")
        
    elif response.status_code == 404:
        print("❌ Not Found (404)")
        print("The database is empty or the URL is incorrect.")
        print("\nVerifying database details:")
        print(f"  Project: {project_id}")
        print(f"  Database URL: {database_url}")
        print(f"  Expected path: {database_url}/.json")
        
    else:
        print(f"❌ Error {response.status_code}")
        print(f"Response: {response.text[:300]}")
        
except requests.exceptions.Timeout:
    print("❌ Connection timeout")
    print("Firebase server not responding")
    
except Exception as e:
    print(f"❌ Error: {e}")
    print(f"   Type: {type(e).__name__}")

print("\n" + "="*70 + "\n")
