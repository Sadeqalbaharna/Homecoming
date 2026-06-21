#!/usr/bin/env python3
"""
Firebase Database Structure Analyzer
Connects to Firebase and displays the database structure
"""

import json
from pathlib import Path

import sys
import os

FIREBASE_KEY_PATH = Path("functions/firebase_service_account.json")

# Check if running from Pi
if not FIREBASE_KEY_PATH.exists():
    FIREBASE_KEY_PATH = Path("/home/pi/kai/firebase_service_account.json")

# Also check current directory
if not FIREBASE_KEY_PATH.exists():
    # Look in Downloads
    FIREBASE_KEY_PATH = Path(os.path.expanduser("~/Downloads/homecoming-74f73-firebase-adminsdk-fbsvc-257ed0f4bd.json"))

print("\n" + "="*60)
print("📊 FIREBASE DATABASE STRUCTURE ANALYZER")
print("="*60 + "\n")

if not FIREBASE_KEY_PATH.exists():
    print(f"❌ ERROR: Firebase credentials not found at {FIREBASE_KEY_PATH}")
    exit(1)

print(f"✓ Loading credentials from {FIREBASE_KEY_PATH}")

# Import firebase after checking path exists
import firebase_admin
from firebase_admin import credentials, db

try:
    # Initialize Firebase safely
    try:
        firebase_admin.initialize_app(credentials.Certificate(str(FIREBASE_KEY_PATH)), {
            "databaseURL": "https://homecoming-kai-default-rtdb.firebaseio.com/"
        })
    except ValueError:
        # Already initialized, that's fine
        pass
    
    print("✓ Connected to Firebase\n")
except Exception as e:
    print(f"❌ Firebase initialization failed: {e}")
    print(f"   {type(e).__name__}")
    exit(1)

# Get database reference
db_ref = db.reference()

def print_tree(ref, prefix="", depth=0, max_depth=4):
    """Recursively print database tree structure"""
    if depth > max_depth:
        print(f"{prefix}  ... (max depth reached)")
        return
    
    try:
        data = ref.get()
        
        if data is None:
            print(f"{prefix}  (empty)")
            return
        
        if isinstance(data, dict):
            items = list(data.items())
            for i, (key, value) in enumerate(items):
                is_last = (i == len(items) - 1)
                current_prefix = "└── " if is_last else "├── "
                next_prefix = "    " if is_last else "│   "
                
                # Determine what to show
                if isinstance(value, dict):
                    print(f"{prefix}{current_prefix}{key}/ ({len(value)} items)")
                    new_ref = ref.child(key)
                    print_tree(new_ref, prefix + next_prefix, depth + 1, max_depth)
                elif isinstance(value, (str, int, float, bool)):
                    # Truncate long values
                    val_str = str(value)
                    if len(val_str) > 50:
                        val_str = val_str[:47] + "..."
                    print(f"{prefix}{current_prefix}{key}: {val_str}")
                else:
                    print(f"{prefix}{current_prefix}{key}: {type(value).__name__}")
        elif isinstance(data, list):
            print(f"{prefix}  (array with {len(data)} items)")
        else:
            data_str = str(data)
            if len(data_str) > 50:
                data_str = data_str[:47] + "..."
            print(f"{prefix}  {data_str}")
    except Exception as e:
        print(f"{prefix}  ❌ Error reading: {e}")

print("DATABASE STRUCTURE:\n")
print("root/")
print_tree(db_ref)

print("\n" + "="*60)

# Get statistics
try:
    all_data = db_ref.get()
    if all_data:
        def count_entries(data, count=0):
            if isinstance(data, dict):
                for value in data.values():
                    count = count_entries(value, count) + 1
            return count
        
        total_entries = count_entries(all_data)
        print(f"\n📈 STATISTICS:")
        print(f"  Total keys: {total_entries}")
        
        # Check specific paths
        tables_ref = db_ref.child("tables")
        tables_data = tables_ref.get()
        if tables_data:
            table_count = len(tables_data) if isinstance(tables_data, dict) else 0
            print(f"  Tables: {table_count}")
            
            if table_count > 0:
                first_table = list(tables_data.keys())[0]
                table_ref = tables_ref.child(first_table)
                table_data = table_ref.get()
                
                if isinstance(table_data, dict):
                    convos = table_data.get("conversations")
                    if convos and isinstance(convos, dict):
                        print(f"  Conversations in {first_table}: {len(convos)}")

except Exception as e:
    print(f"\n⚠️  Could not get statistics: {e}")

print("\n" + "="*60)
