#!/usr/bin/env python3
"""
migrate_to_rtdb.py
──────────────────
One-shot migration: reads every collection from kingdom-ac44f Firestore
and writes it into kingdom-ac44f RTDB via the REST API.

Collections migrated:
  users/{uid}                           → /users/{uid}/profile
  users/{uid}/kai_memory/facts          → /users/{uid}/kai_memory
  users/{uid}/kai_conversations/{date}  → /users/{uid}/kai_conversations/{date}
  users/{uid}/orders/{id}               → /users/{uid}/orders/{id}
  users/{uid}/checkins/{id}             → /users/{uid}/checkins/{id}

Run from scripts/firebase/:
  python3 migrate_to_rtdb.py [--dry-run]

Requires serviceAccountKey.json for the kingdom-ac44f project in the same directory.
Download from: Firebase Console → kingdom-ac44f → Project Settings → Service Accounts
"""

import argparse
import json
import sys
import time
import requests
import firebase_admin
from firebase_admin import credentials, firestore

# ── Config ────────────────────────────────────────────────────────────────────

RTDB            = 'https://kingdom-ac44f-default-rtdb.europe-west1.firebasedatabase.app'
SERVICE_ACCOUNT = 'serviceAccountKey.json'

# ── Args ──────────────────────────────────────────────────────────────────────

parser = argparse.ArgumentParser()
parser.add_argument('--dry-run', action='store_true', help='Preview only — no writes')
args   = parser.parse_args()

DRY_RUN = args.dry_run
if DRY_RUN:
    print('🔍 DRY RUN — no writes will happen\n')

# ── Init ──────────────────────────────────────────────────────────────────────

try:
    firebase_admin.initialize_app(credentials.Certificate(SERVICE_ACCOUNT))
    fs = firestore.client()
    print('✅ Firestore connected (kingdom-ac44f)')
except Exception as e:
    print(f'❌ Firestore init failed: {e}')
    print('   Download serviceAccountKey.json from:')
    print('   Firebase Console → kingdom-ac44f → Project Settings → Service Accounts')
    sys.exit(1)

stats = {'read': 0, 'written': 0, 'errors': 0}

# ── Helpers ───────────────────────────────────────────────────────────────────

def rtdb_put(path: str, data: dict):
    stats['read'] += 1
    if DRY_RUN:
        print(f'  [DRY] PUT /{path}  →  {json.dumps(data)[:120]}')
        return
    try:
        resp = requests.put(f'{RTDB}/{path}.json', json=data, timeout=10)
        if resp.ok:
            stats['written'] += 1
        else:
            print(f'  ⚠️  PUT /{path}: {resp.status_code} {resp.text[:80]}')
            stats['errors'] += 1
    except Exception as e:
        print(f'  ⚠️  PUT /{path}: {e}')
        stats['errors'] += 1


def _serialize(val):
    """Convert Firestore types to plain JSON-safe values."""
    import datetime
    if isinstance(val, dict):
        return {k: _serialize(v) for k, v in val.items()}
    if isinstance(val, list):
        return [_serialize(v) for v in val]
    if isinstance(val, datetime.datetime):
        return int(val.timestamp() * 1000)
    if hasattr(val, 'seconds') and hasattr(val, 'nanos'):  # Firestore Timestamp
        return int(val.seconds * 1000 + val.nanos // 1_000_000)
    return val


# ── Migration ─────────────────────────────────────────────────────────────────

def migrate_users():
    print('\n── users ──')
    users = list(fs.collection('users').stream())
    print(f'   Found {len(users)} user(s)')

    for user in users:
        uid  = user.id
        data = _serialize(user.to_dict())

        # Profile
        rtdb_put(f'users/{uid}/profile', data)

        # kai_memory
        try:
            mem = fs.collection('users').document(uid) \
                    .collection('kai_memory').document('facts').get()
            if mem.exists:
                rtdb_put(f'users/{uid}/kai_memory', _serialize(mem.to_dict()))
        except Exception as e:
            print(f'   ⚠️  kai_memory {uid}: {e}')

        # kai_conversations
        try:
            convs = list(fs.collection('users').document(uid)
                           .collection('kai_conversations').stream())
            for conv in convs:
                rtdb_put(f'users/{uid}/kai_conversations/{conv.id}',
                         _serialize(conv.to_dict()))
        except Exception as e:
            print(f'   ⚠️  conversations {uid}: {e}')

        # orders
        try:
            orders = list(fs.collection('users').document(uid)
                            .collection('orders').stream())
            for order in orders:
                rtdb_put(f'users/{uid}/orders/{order.id}',
                         _serialize(order.to_dict()))
        except Exception as e:
            print(f'   ⚠️  orders {uid}: {e}')

        # checkins
        try:
            checkins = list(fs.collection('users').document(uid)
                              .collection('checkins').stream())
            for ci in checkins:
                rtdb_put(f'users/{uid}/checkins/{ci.id}',
                         _serialize(ci.to_dict()))
        except Exception as e:
            print(f'   ⚠️  checkins {uid}: {e}')

        print(f'   ✓ {uid} ({data.get("username") or data.get("name") or "?"})')


# ── Run ───────────────────────────────────────────────────────────────────────

print('Migration: kingdom-ac44f Firestore → kingdom-ac44f RTDB')
t0 = time.time()

try:
    migrate_users()
except Exception as e:
    print(f'\n❌ Migration aborted: {e}')
    sys.exit(1)

elapsed = round(time.time() - t0, 1)
print(f'\n{"─" * 50}')
print(f'✅ Done in {elapsed}s')
print(f'   Read:    {stats["read"]}')
print(f'   Written: {stats["written"]}')
print(f'   Errors:  {stats["errors"]}')

if stats['errors']:
    print('\n⚠️  Some writes failed. Re-run to retry (PUT is idempotent).')
