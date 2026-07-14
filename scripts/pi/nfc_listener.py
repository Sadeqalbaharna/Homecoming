#!/usr/bin/env python3
"""
tavern_station/nfc_listener.py — The Tavern table station.

Single source of truth: RTDB (kingdom-ac44f), all via REST. This file used
to talk to Firestore directly; that path was migrated away some time ago
in favor of the REST helpers below, but this docstring never got updated
to say so — if you're reading old comments elsewhere that mention
Firestore for any of this, they're stale.

RTDB layout managed here:
  nfc_links/{nfc_uid}                   → { authUid }  — customer badge link
  staff_badges/{nfc_uid}                → { name, role, staffId } — staff badge
                                           link (reverse-index of staff_assignments,
                                           maintained by the console's Staff
                                           Assignment modal — see staffAssignSave()
                                           in tavern_console.html)
  users/{auth_uid}/profile              → visitCount, lastVisit, nfcUid (this
                                           file's own bookkeeping fields; the
                                           Kingdom app's Kai reads other keys —
                                           points/gold/faction/notes — from this
                                           same node, written elsewhere)
    checkins/{auto_id}                  → { tableId, tableName, arrivedAt }
    kai_memory/facts                    → { facts: [...] }  read + written here
    kai_conversations/{date}_table      → { messages, source:'table', updatedAt }
  tavern_guests/{nfc_uid}               → PERSISTENT unlinked-guest profile
                                           (no Kingdom app), keyed by badge UID.
                                           NOTE: the console/app ALSO write
                                           tavern_guests/{tableId} (a *different*,
                                           EPHEMERAL "who's seated here right now"
                                           marker, deleted on close/depart) — same
                                           collection, two different key schemes
                                           for two different purposes. Don't
                                           confuse the two when reading this path.
    checkins/{auto_id}                  → { tableId, tableName, arrivedAt }

Visit + staff flow:
  visits/{visit_id}                     → { tableId, nfcUid, authUid, items[],
                                             total, status } — opened on seat,
                                             POS fills items/total
  users/{auth_uid}/visits/{visit_id}    → archived copy on close (per-customer spend)
  tables/{table_id}                     → current occupant + visitId; cleared
                                           (PATCH-null, not deleted — a table
                                           layout PATCH from the console keeps a
                                           `name` field on this same node) on
                                           staff-badge close
  active_guests/{nfc_uid}               → live presence keyed by THIS station's
                                           badge UID. The console's own seating
                                           flows (Tables tab walk-ins, Reservation
                                           "Seat Now") key their own active_guests
                                           entries differently (by app account uid
                                           or a synthetic guest_id, since there's
                                           no physical badge involved) — close_table()
                                           below scans by the `tableId` field
                                           instead of assuming one key convention,
                                           so it can clear a table regardless of
                                           which system originally seated it.

Per-table config via environment:
  TABLE_ID=table-3 TABLE_NAME="Window Booth" python3 nfc_listener.py
"""

import os
import sys
import time
import random
import signal
import datetime
import wave
import io
import json
import threading
import subprocess
import requests
import numpy as np

# firebase_admin — used for ALL RTDB reads/writes below via db.reference(),
# NOT bare REST calls. This used to be a stale, unused import ("kept only
# for NFC link resolution during transition period" — that comment was
# wrong; the db submodule was never even imported). Every RTDB helper
# below now goes through the Admin SDK instead, which authenticates as a
# trusted server and bypasses the security-rules checks entirely — the
# same pattern kai_station.py already used successfully. Bare, unauthenticated
# `requests.get/put/patch/delete` calls against the *.firebasedatabase.app
# REST endpoint (the old approach) started failing with 401 the moment
# database.rules.json was tightened to require `auth != null` (and, for
# `tables`/`staff_badges`/`users`, staff membership or an exact uid match)
# — something a Pi station acting on behalf of arbitrary tapped-in guests
# can never satisfy via a single fixed REST token anyway. Admin SDK access
# sidesteps that whole problem.
import firebase_admin
from firebase_admin import credentials
from firebase_admin import db

try:
    import pyaudio
    PYAUDIO_AVAILABLE = True
except ImportError:
    PYAUDIO_AVAILABLE = False
    print('pyaudio not installed — pip install pyaudio')

try:
    from openai import OpenAI as _OpenAI
    OPENAI_AVAILABLE = True
except ImportError:
    OPENAI_AVAILABLE = False
    print('openai not installed — pip install openai')

try:
    from smartcard.System import readers
    from smartcard.util import toHexString
    SMARTCARD_AVAILABLE = True
except ImportError:
    print('pyscard not installed — pip install pyscard')
    SMARTCARD_AVAILABLE = False
    def readers(): return []
    def toHexString(data): return ''


# ── Config ────────────────────────────────────────────────────────────────────

TABLE_ID      = os.environ.get('TABLE_ID',       'table-1')
TABLE_NAME    = os.environ.get('TABLE_NAME',      'Table 1')
SLEEP_TIMEOUT = int(os.environ.get('SLEEP_TIMEOUT', '300'))  # seconds idle → sleep

SERVICE_ACCOUNT  = os.path.join(os.path.dirname(__file__), 'serviceAccountKey.json')
ELEVENLABS_KEY   = os.environ.get('ELEVENLABS_KEY', '')
KAI_VOICE_ID     = os.environ.get('KAI_VOICE_ID',  '')
OPENAI_KEY       = os.environ.get('OPENAI_KEY',    '')
AUDIO_OUTPUT_CMD = 'mpg123 -q -a plughw:2,0 -'

MAX_TURNS         = 1   # greet → one reply → done; deeper chat lives in the Kingdom app
SILENCE_THRESHOLD = 600
SILENCE_DURATION  = 1.8
MAX_RECORD_SECS   = 25
MIC_RATE          = 16000
MIC_CHANNELS      = 1
MIC_CHUNK         = 1024

NUDGE_TIMEOUT     = 60   # seconds idle before Kai mentions the Kingdom app
DEBOUNCE_SECS     = 8
GET_UID           = [0xFF, 0xCA, 0x00, 0x00, 0x00]

# ── Firebase ─────────────────────────────────────────────────────────────────
# kingdom-ac44f project — the same RTDB the console and Kingdom app both
# read/write. Admin SDK access here is trusted/server-side, so it bypasses
# database.rules.json entirely (no auth != null / staff-membership checks
# apply) — exactly the access level this station actually needs, since it
# reads/writes on behalf of whichever guest or staff member just tapped a
# badge, not a single fixed account the rules could reasonably grant a
# REST token to.

_TAVERN_RTDB_BASE = 'https://kingdom-ac44f-default-rtdb.europe-west1.firebasedatabase.app'

firebase_admin.initialize_app(
    credentials.Certificate(SERVICE_ACCOUNT),
    {'databaseURL': _TAVERN_RTDB_BASE},
)
print('Firebase Admin initialized (RTDB via Admin SDK — bypasses security rules)')


def _rtdb_put(path: str, data: dict) -> None:
    """Set (overwrite) a path in kingdom-ac44f RTDB. Fire-and-forget; errors are non-fatal."""
    try:
        db.reference(path).set(data)
    except Exception as e:
        print(f'RTDB put {path}: {e}')


def _rtdb_delete(path: str) -> None:
    """Delete a path from kingdom-ac44f RTDB."""
    try:
        db.reference(path).delete()
    except Exception as e:
        print(f'RTDB delete {path}: {e}')


def _rtdb_patch(path: str, data: dict) -> None:
    """Merge-update a path in kingdom-ac44f RTDB. Keys set to None are deleted
    (same semantics as the old REST PATCH this replaced)."""
    try:
        db.reference(path).update(data)
    except Exception as e:
        print(f'RTDB patch {path}: {e}')


def _rtdb_get(path: str):
    """Get a path from kingdom-ac44f RTDB. Returns the parsed value or None."""
    try:
        return db.reference(path).get()
    except Exception as e:
        print(f'RTDB get {path}: {e}')
        return None


# ══════════════════════════════════════════════════════════════════════════════
#  DISPLAY
# ══════════════════════════════════════════════════════════════════════════════

_DISPLAY     = os.environ.get('DISPLAY', '')           # empty = no display attached
HAS_DISPLAY  = bool(_DISPLAY)                           # set DISPLAY=:0 in env to enable

def _detect_mic() -> bool:
    """Returns True if at least one input device is available."""
    if not PYAUDIO_AVAILABLE:
        return False
    try:
        p = pyaudio.PyAudio()
        found = any(
            p.get_device_info_by_index(i).get('maxInputChannels', 0) > 0
            for i in range(p.get_device_count())
        )
        p.terminate()
        return found
    except Exception:
        return False

HAS_MIC = _detect_mic()
_sleep_timer: threading.Timer | None = None
_nudge_timer: threading.Timer | None = None
_sleep_lock  = threading.Lock()


def display_wake():
    if not HAS_DISPLAY:
        return
    env = {**os.environ, 'DISPLAY': _DISPLAY}
    subprocess.run(['xset', 'dpms', 'force', 'on'], env=env, stderr=subprocess.DEVNULL)
    subprocess.run(['xset', 's', 'reset'],           env=env, stderr=subprocess.DEVNULL)


def display_sleep():
    if not HAS_DISPLAY:
        return
    print(f'Display sleeping ({SLEEP_TIMEOUT}s idle)')
    env = {**os.environ, 'DISPLAY': _DISPLAY}
    subprocess.run(['xset', 'dpms', 'force', 'off'], env=env, stderr=subprocess.DEVNULL)


# ── Kai's animated face (kai_screen.py, running as a separate process) ──────
# That script polls KAI_STATE_FILE and plays the matching frame loop/
# transition. This is the only thing that writes to it — best-effort, since
# a station with no screen attached just has nothing watching this file.
KAI_STATE_FILE = os.environ.get('KAI_STATE_FILE', '/tmp/kai_state')


def _set_kai_state(state: str):
    """Atomic write (write-then-rename) so kai_screen.py's poll loop, which
    reads this file every 0.1s, never sees a half-written value."""
    try:
        tmp = f'{KAI_STATE_FILE}.tmp'
        with open(tmp, 'w') as f:
            f.write(state)
        os.replace(tmp, KAI_STATE_FILE)
    except OSError as e:
        print(f'kai_state write failed: {e}')


def _cancel_nudge():
    global _nudge_timer
    if _nudge_timer and _nudge_timer.is_alive():
        _nudge_timer.cancel()
    _nudge_timer = None


def _fire_nudge():
    """Spoken after NUDGE_TIMEOUT seconds idle — reminds guest the Kingdom app is waiting."""
    msg = 'If you want to keep talking, I\'ll be right there on your Kingdom app — just open it up.'
    print(f'Kai (nudge): {msg}')
    speak(msg)


def _reset_sleep_timer():
    global _sleep_timer, _nudge_timer
    with _sleep_lock:
        # Cancel both timers
        if _sleep_timer and _sleep_timer.is_alive():
            _sleep_timer.cancel()
        _cancel_nudge()

        # Nudge fires at 1 minute idle
        _nudge_timer = threading.Timer(NUDGE_TIMEOUT, _fire_nudge)
        _nudge_timer.daemon = True
        _nudge_timer.start()

        # Display sleeps at SLEEP_TIMEOUT
        _sleep_timer = threading.Timer(SLEEP_TIMEOUT, display_sleep)
        _sleep_timer.daemon = True
        _sleep_timer.start()


# ══════════════════════════════════════════════════════════════════════════════
#  IDENTITY RESOLUTION
# ══════════════════════════════════════════════════════════════════════════════

def lookup_auth_uid(nfc_uid: str) -> str | None:
    """NFC hardware UID → Firebase Auth UID via /nfc_links/{nfc_uid} in RTDB."""
    try:
        data = _rtdb_get(f'nfc_links/{nfc_uid}')
        if data and isinstance(data, dict):
            return data.get('authUid')
        return None
    except Exception as e:
        print(f'nfc_links error: {e}')
        return None


def lookup_staff(nfc_uid: str) -> dict | None:
    """
    Staff badge? → /staff_badges/{nfc_uid} = { name, role, staffId }.
    A staff tap closes a table instead of seating a guest.

    This used to read /staff/{nfc_uid}, a path nothing in the console or app
    ever wrote to — so staff badge taps never actually closed a table. Staff
    badges are registered via the console's Staff tab → Assign → NFC Badge
    UID field (staffAssignSave() in tavern_console.html), which maintains
    this path as a reverse-index of /staff_assignments.
    """
    data = _rtdb_get(f'staff_badges/{nfc_uid}')
    if data and isinstance(data, dict):
        return data
    return None


# ══════════════════════════════════════════════════════════════════════════════
#  CUSTOMER PROFILE
# ══════════════════════════════════════════════════════════════════════════════

def upsert_linked_customer(auth_uid: str, nfc_uid: str) -> dict:
    """
    Read profile from RTDB /users/{uid}/profile, increment visitCount, write back.
    Returns the updated profile dict.
    """
    now_ms = int(time.time() * 1000)
    try:
        profile = _rtdb_get(f'users/{auth_uid}/profile') or {}
    except Exception:
        profile = {}

    # Capture the ACTUAL previous visit before we stamp "now" over it below —
    # build_greeting() needs "last time you were here" to mean something
    # other than "right now". Previously this was read after the overwrite,
    # so every greeting silently lost this fact.
    prev_last_visit = profile.get('lastVisit')

    visit_count = (profile.get('visitCount') or 0) + 1
    profile.update({'visitCount': visit_count, 'lastVisit': now_ms, 'nfcUid': nfc_uid})
    _rtdb_put(f'users/{auth_uid}/profile', profile)

    name = profile.get('username') or profile.get('name') or 'traveller'
    print(f'{name} — visit #{visit_count}')
    profile['_prevLastVisit'] = prev_last_visit
    return profile


def upsert_guest(nfc_uid: str) -> dict:
    """
    Unlinked guest (no Kingdom app). Uses /tavern_guests/{nfc_uid} in RTDB.
    """
    now_ms = int(time.time() * 1000)
    try:
        profile = _rtdb_get(f'tavern_guests/{nfc_uid}') or {}
    except Exception:
        profile = {}

    visit_count = (profile.get('visitCount') or 0) + 1
    prev_last_visit = profile.get('lastVisit')  # see upsert_linked_customer above

    if not profile:
        profile = {'name': 'Guest', 'visitCount': 1,
                   'firstVisit': now_ms, 'lastVisit': now_ms,
                   'notes': '', 'isVIP': False}
        print(f'New unlinked guest: {nfc_uid}')
    else:
        profile['visitCount'] = visit_count
        profile['lastVisit']  = now_ms

    _rtdb_put(f'tavern_guests/{nfc_uid}', profile)
    profile['_prevLastVisit'] = prev_last_visit
    return profile


def write_checkin(auth_uid: str | None, nfc_uid: str, profile: dict):
    """Write arrival record and update table occupancy — RTDB only."""
    now_ms = int(time.time() * 1000)

    # ── Checkin history ───────────────────────────────────────────────────────
    checkin = {'tableId': TABLE_ID, 'tableName': TABLE_NAME,
               'nfcUid': nfc_uid, 'arrivedAt': now_ms}
    checkin_key = str(now_ms)
    if auth_uid:
        _rtdb_put(f'users/{auth_uid}/checkins/{checkin_key}', checkin)
    else:
        _rtdb_put(f'tavern_guests/{nfc_uid}/checkins/{checkin_key}', checkin)

    # ── RTDB live table/guest state ───────────────────────────────────────────
    guest_name  = profile.get('username') or profile.get('name') or 'Guest'
    visit_count = profile.get('visitCount', 1)
    is_vip      = bool(profile.get('isVIP', False))
    usual_order = profile.get('usualOrder', '')
    notes       = profile.get('notes', '')

    # ── Open a visit — the order/spend ledger. POS fills items+total later; the
    #    staff close routine archives this onto the customer's account. ──────────
    visit_id = f'{TABLE_ID}_{now_ms}'
    _rtdb_put(f'visits/{visit_id}', {
        'visitId':   visit_id,
        'nfcUid':    nfc_uid,
        'authUid':   auth_uid or '',
        'tableId':   TABLE_ID,
        'tableName': TABLE_NAME,
        'guestName': guest_name,
        'openedAt':  now_ms,
        'status':    'open',
        'source':    'pos',
        'items':     [],
        'total':     0,
    })

    # /tables/{tableId} — current occupant of this table. PATCH (merge), not
    # PUT — the console's floor-layout editor (cloudSave()) also writes a
    # `name` field onto this same node, and a PUT would silently wipe it.
    _rtdb_patch(f'tables/{TABLE_ID}', {
        'tableName':    TABLE_NAME,
        'guestName':    guest_name,
        'guestAuthUid': auth_uid or '',
        'guestNfcUid':  nfc_uid,
        'visitId':      visit_id,
        'visitCount':   visit_count,
        'isVIP':        is_vip,
        'usualOrder':   usual_order,
        'arrivedAt':    now_ms,
    })

    # /active_guests/{nfcUid} — guest-keyed presence record
    _rtdb_put(f'active_guests/{nfc_uid}', {
        'name':       guest_name,
        'authUid':    auth_uid or '',
        'tableId':    TABLE_ID,
        'tableName':  TABLE_NAME,
        'visitId':    visit_id,
        'visitCount': visit_count,
        'isVIP':      is_vip,
        'usualOrder': usual_order,
        'notes':      notes,
        'arrivedAt':  now_ms,
        'isLinked':   auth_uid is not None,
    })


def _do_close_table(staff_uid: str) -> dict | None:
    """
    Does the actual work of closing this station's table: archives the visit
    onto the customer's account (per-customer history + lifetime spend), then
    removes the live presence. Returns {'occName', 'total'} on success, or
    None if the table was already free (nothing to do).

    Pulled out of close_table() so both the legacy instant-close badge path
    AND the new app-confirmed path (see _push_staff_prompt/
    _await_staff_prompt_answer below) share one implementation — a table
    should get freed exactly the same way regardless of which path triggered
    it.
    """
    now_ms = int(time.time() * 1000)
    table  = _rtdb_get(f'tables/{TABLE_ID}') or {}

    if not table.get('arrivedAt'):
        return None

    occ_auth = table.get('guestAuthUid')
    occ_name = table.get('guestName', 'the guest')
    visit_id = table.get('visitId')

    # Archive the visit (POS total, if any) ─────────────────────────────────────
    visit = (_rtdb_get(f'visits/{visit_id}') if visit_id else None) or {}
    total = visit.get('total', 0) or 0
    visit.update({'status': 'closed', 'closedAt': now_ms, 'closedBy': staff_uid})
    if visit_id:
        _rtdb_put(f'visits/{visit_id}', visit)
        if occ_auth:                                   # per-customer history
            _rtdb_put(f'users/{occ_auth}/visits/{visit_id}', visit)

    # Lifetime spend on the linked account ──────────────────────────────────────
    if occ_auth and total:
        prof = _rtdb_get(f'users/{occ_auth}/profile') or {}
        prof['totalSpend'] = (prof.get('totalSpend') or 0) + total
        _rtdb_put(f'users/{occ_auth}/profile', prof)

    # Free the table + clear live presence ──────────────────────────────────────
    # Scan by the `tableId` field rather than trusting occ_uid (=guestNfcUid) —
    # that only matches guests THIS Pi seated. A guest seated via the
    # console's Tables tab or a reservation "Seat Now" has an active_guests
    # entry keyed by an app-account uid or a synthetic guest_id instead, and
    # occ_uid would be empty for them, leaving a ghost "occupied" entry
    # behind. Scanning + matching on the field (mirroring tablesCloseTable()'s
    # own approach in tavern_console.html) clears the table no matter which
    # system originally seated it.
    all_active = _rtdb_get('active_guests') or {}
    if isinstance(all_active, dict):
        for key, g in all_active.items():
            if isinstance(g, dict) and g.get('tableId') == TABLE_ID:
                _rtdb_delete(f'active_guests/{key}')

    # Clear the ephemeral /tavern_guests/{TABLE_ID} "who's seated here right
    # now" entry written by the console's bookingSeatNow() or the app's own
    # self-checkin (visit_service.dart). This is a DIFFERENT record from this
    # Pi's own persistent /tavern_guests/{nfc_uid} guest-profile entries
    # (keyed by badge UID, never touched by this delete) — see the module
    # docstring for why the same collection holds both.
    _rtdb_delete(f'tavern_guests/{TABLE_ID}')

    _rtdb_patch(f'tables/{TABLE_ID}', {
        'arrivedAt': None, 'guestName': None, 'guestNfcUid': None,
        'guestAuthUid': None, 'visitId': None, 'visitCount': None,
        'isVIP': None, 'usualOrder': None,
    })

    return {'occName': occ_name, 'total': total}


def close_table(staff_uid: str, staff_name: str = 'staff') -> None:
    """
    LEGACY instant-close path — staff tapped a badge registered the old way
    (console's Staff Assignments modal, /staff_badges/{nfc_uid}, no linked
    app account). No app to send a confirmation to, so this still closes
    immediately like it always has. Staff who've linked their badge via the
    Kingdom app (see NfcLinkScreen + Staff Panel's on-shift toggle) go
    through the NEW confirm-first path in _handle_tap instead — see that
    function's comment for how the two are told apart.
    """
    table = _rtdb_get(f'tables/{TABLE_ID}') or {}
    if not table.get('arrivedAt'):
        print(f'{TABLE_NAME} already free — nothing to close')
        speak('This table is already clear.')
        return

    result = _do_close_table(staff_uid)
    if result is None:
        speak('This table is already clear.')
        return

    print(f"{staff_name} closed {TABLE_NAME} — guest {result['occName']}, total {result['total']} BHD")
    speak('Table cleared. Until next time.')


# ══════════════════════════════════════════════════════════════════════════════
#  KAI MEMORY  (shared with Kingdom app — RTDB /users/{uid}/kai_memory)
# ══════════════════════════════════════════════════════════════════════════════

def load_kai_memory(auth_uid: str) -> list[str]:
    try:
        data = _rtdb_get(f'users/{auth_uid}/kai_memory')
        if isinstance(data, dict):
            return data.get('facts', [])
        return []
    except Exception as e:
        print(f'Memory load error: {e}')
        return []


def extract_and_save_memory(auth_uid: str, user_text: str, kai_reply: str):
    """
    Fire-and-forget memory extraction — mirrors kai_service.dart logic.
    Runs after every exchange so Pi conversations enrich the shared memory
    that Kingdom app Kai also reads.
    """
    def _do():
        try:
            existing = load_kai_memory(auth_uid)
            prompt = f"""You are a fact extractor. Extract NEW personal facts the customer shared.
Return ONLY a JSON array of short strings. Return [] if nothing new.
Do NOT repeat: {'; '.join(existing) if existing else 'none yet'}
Rules: relationships, preferences, allergies, life events, nicknames only — no guesses.

Customer said: "{user_text}"
Kai replied: "{kai_reply}"

JSON array:"""

            client = _OpenAI(api_key=OPENAI_KEY)
            resp   = client.chat.completions.create(
                model='gpt-4o-mini',
                messages=[{'role': 'user', 'content': prompt}],
                max_tokens=150, temperature=0.2,
            )
            raw      = resp.choices[0].message.content.strip()
            json_str = next((m.group(0) for m in [__import__('re').search(r'\[.*\]', raw, __import__('re').DOTALL)] if m), '[]')
            new_facts = [f for f in json.loads(json_str) if isinstance(f, str) and f.strip()]

            if not new_facts:
                return

            merged = existing + new_facts
            capped = merged[-60:] if len(merged) > 60 else merged

            _rtdb_put(f'users/{auth_uid}/kai_memory',
                      {'facts': capped, 'updatedAt': int(time.time() * 1000)})
            print(f'Memory updated: +{len(new_facts)} fact(s)')

        except Exception as e:
            print(f'Memory extraction error: {e}')

    threading.Thread(target=_do, daemon=True).start()


def save_conversation(auth_uid: str, messages: list[dict]):
    """
    Save Pi conversation to RTDB /users/{uid}/kai_conversations/{session_id}.
    Tagged source='table' so it's distinguishable from app conversations.
    """
    if not messages or not auth_uid:
        return
    try:
        today      = datetime.datetime.now().strftime('%Y-%m-%d')
        session_id = f'{today}_table_{TABLE_ID}'
        _rtdb_put(f'users/{auth_uid}/kai_conversations/{session_id}', {
            'messages':  messages,
            'source':    'table',
            'tableId':   TABLE_ID,
            'tableName': TABLE_NAME,
            'updatedAt': int(time.time() * 1000),
        })
    except Exception as e:
        print(f'Conversation save error: {e}')


# ══════════════════════════════════════════════════════════════════════════════
#  ORDER HISTORY  (RTDB /users/{uid}/orders — mirrored there by order_service
#  .dart's placeOrder()/advanceStatus()/cancelOrder(), 2026-07 fix. Before
#  that fix this path was never written at all, so this always returned
#  nothing — mirrors kai_service.dart's _loadStructuredContext() in Python.)
# ══════════════════════════════════════════════════════════════════════════════

def _load_order_context(auth_uid: str | None) -> str:
    """Recent order history + favourite items for a linked customer, pulled
    from the same RTDB path the app's own Kai chat reads. Returns '' for
    unlinked guests or anyone with no order history yet."""
    if not auth_uid:
        return ''
    try:
        raw = _rtdb_get(f'users/{auth_uid}/orders')
    except Exception as e:
        print(f'Order context fetch error: {e}')
        raw = None
    if not raw or not isinstance(raw, dict):
        return ''

    orders = sorted(
        (o for o in raw.values() if isinstance(o, dict)),
        key=lambda o: o.get('createdAt', 0), reverse=True,
    )[:30]
    if not orders:
        return ''

    item_count: dict[str, int] = {}
    for o in orders:
        for item in (o.get('items') or []):
            if not isinstance(item, dict):
                continue
            name = item.get('name', '')
            qty  = item.get('quantity', 1) or 1
            if name:
                item_count[name] = item_count.get(name, 0) + qty
    top_items = sorted(item_count.items(), key=lambda kv: kv[1], reverse=True)[:3]

    lines = [f'Total orders placed: {len(orders)}']
    if top_items:
        lines.append('Favourite items: ' + ', '.join(n for n, _ in top_items))

    active = [o for o in orders if o.get('status') in ('pending', 'preparing', 'ready')]
    if active:
        active_names = ', '.join(
            i.get('name', '') for i in (active[0].get('items') or []) if isinstance(i, dict)
        )
        if active_names:
            lines.append(f'Has an active order in progress right now: {active_names}')

    return '\n'.join(lines)


# ══════════════════════════════════════════════════════════════════════════════
#  GREETING
# ══════════════════════════════════════════════════════════════════════════════

def _fmt_ago(ms: int | None) -> str:
    """ms timestamp → 'today' / 'yesterday' / '3 days ago' / '' if unknown."""
    if not ms:
        return ''
    diff = time.time() - (ms / 1000)
    if diff < 0:      return ''
    if diff < 3600:   return 'earlier today'
    if diff < 86400:  return 'today'
    days = int(diff // 86400)
    if days == 1:     return 'yesterday'
    if days < 7:      return f'{days} days ago'
    if days < 14:     return 'last week'
    weeks = days // 7
    return f'{weeks} weeks ago'


def build_greeting(profile: dict, memory_facts: list[str],
                    order_ctx: str = '') -> tuple[str, dict]:
    """
    Returns (spoken_greeting, ctx) where ctx carries the same facts Kai just
    used, so the caller can push an identical "recommendation action" card to
    the Kingdom app (see _push_kai_prompt below) without recomputing anything
    or risking the two surfaces disagreeing with each other.
    """
    name    = profile.get('username') or profile.get('name') or 'traveller'
    visits  = profile.get('visitCount', 1)
    usual   = profile.get('usualOrder', '')
    notes   = profile.get('notes', '')
    ago     = _fmt_ago(profile.get('_prevLastVisit'))
    suggested = _pick_suggested_item(usual)
    quest     = _today_quest()

    ctx = {
        'prevLastVisit': profile.get('_prevLastVisit'),
        'usual':         usual,
        'suggested':     suggested,
        'quest':         quest,
    }

    if not OPENAI_AVAILABLE or not OPENAI_KEY:
        text = (f'Back again, {name}. Good to see you.'
                if visits > 1 else 'Welcome to the Tavern, traveller.')
        return text, ctx

    memory_block = '\n'.join(f'- {f}' for f in memory_facts) if memory_facts else '- Nothing yet'
    order_block  = f'\n\nORDER HISTORY:\n{order_ctx}' if order_ctx else ''
    quest_line   = f"- Today's quest on offer: {quest['text']}" if quest else '- No quest live today'

    prompt = f"""You are Kai — the living spirit of The Tavern, a medieval fantasy bar in Bahrain.
A hero just tapped their NFC badge at {TABLE_NAME}. Greet them now — OUT LOUD, spoken word.

HERO PROFILE:
- Registered name: {name}
- Visit number: {visits}
- Last time they were here: {ago or 'this is their first visit'}
- Usual order: {usual or 'not noted yet'}
- Something they haven't tried: {suggested or 'nothing picked yet'}
- Notes: {notes or 'none'}{order_block}
{quest_line}

WHAT YOU REMEMBER ABOUT THEM:
{memory_block}

VOICE — this is the whole point, don't undersell it:
- You have BITE. Dry, knowing, a little cheeky — like a bartender who's seen
  this hero make the same order fifty times and finds it funny, not a
  concierge reciting facts back at them.
- Reference something SPECIFIC and true (their usual, how long it's been,
  a memory fact) — never a generic "welcome back". Prove you actually
  remember them, don't announce that you do.
- First-timers get warmth and atmosphere instead — no history to needle them
  about yet, so lean into "you're new here, let's fix that."
- ONE or TWO sentences, spoken aloud — punchy, not a paragraph.
- End by nudging them to check their phone for options (a card with their
  usual, something new, and today's quest is waiting there) — work this in
  naturally, don't just tack on "check your phone."
- Never start with "Ah," — never mention technology, AI, or apps by name
  (say "your Kingdom app" or "your phone", never "the app" flatly).

Example of the tone we want (for a returning regular, NOT to be copied
verbatim — write a fresh one every time):
"{name}. Back again. Last time you went for the usual — pretending you're
browsing tonight, or should I just summon it? Options are on your phone."
"""

    try:
        resp = _OpenAI(api_key=OPENAI_KEY).chat.completions.create(
            model='gpt-4o-mini',
            messages=[{'role': 'user', 'content': prompt}],
            max_tokens=90, temperature=0.95,
        )
        return resp.choices[0].message.content.strip(), ctx
    except Exception as e:
        print(f'Greeting error: {e}')
        text = f'Back again, {name}.' if visits > 1 else 'Welcome to the Tavern.'
        return text, ctx


# ══════════════════════════════════════════════════════════════════════════════
#  TTS
# ══════════════════════════════════════════════════════════════════════════════

def _espeak_fallback(text: str):
    os.system(f'espeak -v en+m3 -s 140 "{text}" 2>/dev/null')


def speak(text: str):
    if not ELEVENLABS_KEY or not KAI_VOICE_ID:
        _espeak_fallback(text)
        return
    try:
        resp = requests.post(
            f'https://api.elevenlabs.io/v1/text-to-speech/{KAI_VOICE_ID}/stream',
            headers={'xi-api-key': ELEVENLABS_KEY, 'Content-Type': 'application/json'},
            json={'text': text, 'model_id': 'eleven_turbo_v2',
                  'voice_settings': {'stability': 0.5, 'similarity_boost': 0.8}},
            stream=True, timeout=10,
        )
        if resp.status_code != 200:
            print(f'ElevenLabs error: {resp.status_code} {resp.text[:150]}')
            _espeak_fallback(text)
            return

        # stderr was previously swallowed here, which is exactly why a dead
        # audio device (no speaker attached, wrong ALSA card, etc.) showed up
        # as only a bare BrokenPipeError with no explanation. Capture it now
        # so a real mpg123/ALSA failure prints something actionable.
        proc = subprocess.Popen(AUDIO_OUTPUT_CMD.split(),
                                stdin=subprocess.PIPE,
                                stdout=subprocess.DEVNULL,
                                stderr=subprocess.PIPE)
        try:
            for chunk in resp.iter_content(chunk_size=4096):
                if chunk: proc.stdin.write(chunk)
        except BrokenPipeError:
            pass  # mpg123 already died — real reason comes from stderr below
        finally:
            try:
                proc.stdin.close()
            except (BrokenPipeError, OSError, ValueError):
                pass

        # Deliberately NOT using proc.communicate() here — it insists on
        # managing/closing stdin itself, and since we already closed it
        # above, that second close raised "ValueError: flush of closed
        # file", which the outer except caught as a fake failure and fired
        # the espeak fallback mid-playback (audible overlap). Reading
        # stderr directly and wait()'ing avoids touching stdin again. No
        # deadlock risk: stdin is already fully written+closed, and -q mode
        # keeps mpg123's stderr small, so this read won't block on a full
        # pipe buffer.
        err = proc.stderr.read()
        proc.wait()
        if proc.returncode != 0:
            err_text = (err or b'').decode(errors='replace').strip()[:200]
            print(f'mpg123 exited {proc.returncode}: {err_text or "(no stderr output)"}')
            _espeak_fallback(text)
    except Exception as e:
        print(f'TTS error: {e}')
        _espeak_fallback(text)


# ══════════════════════════════════════════════════════════════════════════════
#  CONVERSATION BRAIN
# ══════════════════════════════════════════════════════════════════════════════

_KAI_BASE = """\
You are Kai — the living spirit of The Tavern, a medieval fantasy bar in Bahrain.
Warm, sharp, slightly mysterious. Spoken word — keep replies under 3 sentences.
You know this guest personally. Use their history naturally, never robotically.
Never break character. Never mention AI, apps, or technology.\
"""

# ── Live menu from Tavern RTDB ─────────────────────────────────────────────────
# Fetched once on startup and refreshed every 30 min.
# Falls back to last good cache if the network is unavailable.
# (Uses _rtdb_get() / the Admin SDK — no separate base URL needed here anymore.)

_menu_cache: str = ''
_menu_cache_at: float = 0.0
_MENU_TTL = 30 * 60  # 30 minutes

_CAT_ORDER = [
    'To Share', 'Sandwiches', 'Hearty Meals', 'Flatbread', 'Bowls & Pies',
    'Big Salad Bowl', 'Sweet Tooth', 'Kids Meals', 'Everyday Drinks',
    'Signature Creations', 'Thematic Creations',
]


def _format_menu(raw: dict) -> str:
    """Convert RTDB menu dict into the compact text block Kai reads."""
    cats: dict[str, list] = {c: [] for c in _CAT_ORDER}
    for item in raw.values():
        if not isinstance(item, dict): continue
        cat = item.get('category', 'Other')
        if cat not in cats: cats[cat] = []
        cats[cat].append(item)

    lines = [
        '\nTAVERN MENU & ALLERGENS',
        'Prices in BHD (inclusive of tax). Answer food questions from this list.',
        'For serious allergies always add: "Check with the kitchen to be sure."\n',
    ]
    for cat in _CAT_ORDER:
        items = cats.get(cat, [])
        if not items: continue
        items.sort(key=lambda x: x.get('sortOrder', 0))
        lines.append(cat.upper())
        for it in items:
            if it.get('isAvailable') is False: continue
            name      = it.get('name', '')
            price     = it.get('price', '?')
            allergens = it.get('allergens') or []
            if isinstance(allergens, dict): allergens = list(allergens.values())
            flags = []
            if it.get('isVegetarian'): flags.append('veg')
            if it.get('isVegan'):      flags.append('vegan')
            if it.get('canBeVegan'):   flags.append('vegan-opt')
            if it.get('isGlutenFree'): flags.append('gf')
            allergen_str = ', '.join(allergens) if allergens else 'no major allergens'
            flag_str     = f" | {', '.join(flags)}" if flags else ''
            lines.append(f'- {name} {price} — {allergen_str}{flag_str}')
            if it.get('kaiNotes'):
                lines.append(f"  -> {it['kaiNotes']}")
        lines.append('')
    lines.append('----------------------------')
    return '\n'.join(lines)


_menu_items_cache: list = []  # raw item dicts, kept alongside _menu_cache's
                               # formatted text — build_greeting() needs the
                               # structured list to pick a "something new"
                               # suggestion; the text block alone isn't enough.


def fetch_menu_context() -> str:
    """Return the menu context string, refreshing from RTDB if cache is stale."""
    global _menu_cache, _menu_cache_at, _menu_items_cache
    now = time.time()
    if _menu_cache and (now - _menu_cache_at) < _MENU_TTL:
        return _menu_cache
    try:
        raw = _rtdb_get('menu')
        if raw:
            _menu_cache    = _format_menu(raw)
            _menu_cache_at = now
            _menu_items_cache = [
                it for it in raw.values()
                if isinstance(it, dict) and it.get('isAvailable') is not False
            ]
            print(f'Menu loaded from RTDB ({len(raw)} items)')
        else:
            print('Menu fetch returned nothing — using cache')
    except Exception as e:
        print(f'Menu fetch failed: {e} — using cache')
    return _menu_cache


def _pick_suggested_item(usual: str) -> str:
    """Best-effort 'try something new' pick — a menu item that isn't the
    guest's usual, preferring ones staff have flagged with kaiNotes (curated
    highlights) over a plain random pick. Empty string if the menu hasn't
    loaded yet."""
    if not _menu_items_cache:
        fetch_menu_context()
    items = _menu_items_cache
    if not items:
        return ''
    usual_lower = (usual or '').lower()
    candidates  = [it for it in items if it.get('name', '').lower() not in usual_lower] or items
    starred     = [it for it in candidates if it.get('kaiNotes')]
    pool        = starred or candidates
    return random.choice(pool).get('name', '') if pool else ''


def _today_quest() -> dict | None:
    """'Quest of the day' — deterministic index (days since epoch) into
    whatever pool currently lives at RTDB /quest_pool, so the Pi station and
    the Kingdom app always land on the same pick with no server needed to
    coordinate or persist a choice. Edit the pool in RTDB to change what
    rotates in; the rotation itself needs no redeploy."""
    pool = _rtdb_get('quest_pool')
    if isinstance(pool, dict):
        pool = [pool[k] for k in sorted(pool.keys(), key=lambda x: int(x))]
    if not isinstance(pool, list):
        return None
    pool = [q for q in pool if isinstance(q, dict) and q.get('text')]
    if not pool:
        return None
    day_index = int(time.time() // 86400)
    return pool[day_index % len(pool)]


_conversation_lock = threading.Lock()


def _rms16(data: bytes) -> float:
    """
    RMS of 16-bit PCM audio — replaces stdlib audioop.rms(data, 2), which
    was removed in Python 3.13 (this Pi runs Trixie/3.13). numpy is already
    a hard dependency for kai_screen.py, so no new package needed.
    """
    if not data:
        return 0.0
    samples = np.frombuffer(data, dtype=np.int16).astype(np.float64)
    return float(np.sqrt(np.mean(samples ** 2)))


def _record_audio() -> bytes | None:
    if not PYAUDIO_AVAILABLE: return None
    p = pyaudio.PyAudio()
    try:
        stream = p.open(format=pyaudio.paInt16, channels=MIC_CHANNELS,
                        rate=MIC_RATE, input=True, frames_per_buffer=MIC_CHUNK)
    except OSError:
        p.terminate()
        return None

    frames, has_voice, silent_chunks = [], False, 0
    silence_limit = int(MIC_RATE / MIC_CHUNK * SILENCE_DURATION)
    max_chunks    = int(MIC_RATE / MIC_CHUNK * MAX_RECORD_SECS)

    print('Listening…')
    for _ in range(max_chunks):
        data = stream.read(MIC_CHUNK, exception_on_overflow=False)
        frames.append(data)
        rms = _rms16(data)
        if rms > SILENCE_THRESHOLD:
            has_voice = True; silent_chunks = 0
        elif has_voice:
            silent_chunks += 1
            if silent_chunks >= int(MIC_RATE / MIC_CHUNK * SILENCE_DURATION): break

    stream.stop_stream(); stream.close(); p.terminate()
    if not has_voice: return None

    buf = io.BytesIO()
    with wave.open(buf, 'wb') as wf:
        wf.setnchannels(MIC_CHANNELS); wf.setsampwidth(2)
        wf.setframerate(MIC_RATE); wf.writeframes(b''.join(frames))
    return buf.getvalue()


def _transcribe(audio_bytes: bytes) -> str:
    if not OPENAI_AVAILABLE or not OPENAI_KEY: return ''
    try:
        f      = io.BytesIO(audio_bytes); f.name = 'audio.wav'
        return _OpenAI(api_key=OPENAI_KEY).audio.transcriptions.create(
            model='whisper-1', file=f, language='en').text.strip()
    except Exception as e:
        print(f'Whisper error: {e}'); return ''


def _kai_reply(messages: list, guest_ctx: str) -> str:
    if not OPENAI_AVAILABLE or not OPENAI_KEY: return ''
    try:
        system = _KAI_BASE + fetch_menu_context() + f'\n\nGuest:\n{guest_ctx}'
        return _OpenAI(api_key=OPENAI_KEY).chat.completions.create(
            model='gpt-4o-mini',
            messages=[{'role': 'system', 'content': system}] + messages,
            max_tokens=120, temperature=0.85,
        ).choices[0].message.content.strip()
    except Exception as e:
        print(f'GPT error: {e}'); return ''


def _build_guest_ctx(profile: dict, memory_facts: list[str], order_ctx: str = '') -> str:
    name  = profile.get('username') or profile.get('name') or 'Guest'
    lines = [f'Name: {name}', f'Visit #: {profile.get("visitCount", 1)}']
    if profile.get('usualOrder'): lines.append(f'Usual: {profile["usualOrder"]}')
    if profile.get('notes'):      lines.append(f'Notes: {profile["notes"]}')
    if profile.get('isVIP'):      lines.append('VIP')
    if profile.get('visitCount', 1) == 1: lines.append('(First visit)')
    if order_ctx:
        lines.append('Order history:')
        lines += [f'  {l}' for l in order_ctx.split('\n')]
    if memory_facts:
        lines.append('Memory:')
        lines += [f'  - {f}' for f in memory_facts]
    return '\n'.join(lines)


# ══════════════════════════════════════════════════════════════════════════════
#  RECOMMENDATION ACTION — Pi asks, Kingdom app answers
# ══════════════════════════════════════════════════════════════════════════════
# The mic conversation below (MAX_TURNS) is free-form small talk. This is a
# separate, structured "what do you want to do" prompt: Kai asks it out loud,
# then hands the ANSWER off to the Kingdom app rather than the mic — see
# kai_tab.dart, which polls kai_prompts/{authUid} and renders it as a card
# with three buttons. Kept as its own RTDB node (not reusing kai_memory/
# kai_conversations) so it has a clean pending → answered → done lifecycle
# the app can poll cheaply without diffing conversation history.
#
# App-only for now by design — the mic could resolve the same node later
# (e.g. "just say usual, new, or quest") without any shape change here, but
# that's deliberately out of scope today.
# ══════════════════════════════════════════════════════════════════════════════

_PROMPT_ANSWER_TIMEOUT = 120  # seconds to wait for an app tap before giving up


def _push_kai_prompt(auth_uid: str, ctx: dict):
    """Write the recommendation-action card right after the spoken greeting."""
    quest = ctx.get('quest') or {}
    _rtdb_put(f'kai_prompts/{auth_uid}', {
        'status':     'pending',
        'question':   "Usual, something new, or today's quest?",
        'lastVisit':  ctx.get('prevLastVisit'),
        'usualOrder': ctx.get('usual', ''),
        'suggested':  ctx.get('suggested', ''),
        'quest':      {'id': quest.get('id', ''), 'text': quest.get('text', ''),
                        'points': quest.get('points', 0)} if quest else None,
        'options':    ['usual', 'new', 'quest'],
        'tableId':    TABLE_ID,
        'tableName':  TABLE_NAME,
        'createdAt':  int(time.time() * 1000),
        'answer':     None,
        'answeredAt': None,
    })


def _react_to_prompt_answer(nfc_uid: str, answer: str, ctx: dict):
    """Speak Kai's reaction once the app relays a tap, and flag it for staff.
    Deliberately does NOT auto-place a kitchen order or award faction points
    yet — usualOrder/suggested are free-text and matching them to a real
    priced menu line + notifying the kitchen display is a separate, higher-
    stakes integration. This logs a staff-visible request instead so a human
    confirms the actual order/points, same trust boundary as everywhere else
    money touches this system."""
    if answer == 'usual':
        line = f"The usual it is — {ctx.get('usual') or 'your regular'}. On its way."
        note = {'type': 'order_usual', 'text': ctx.get('usual', '')}
    elif answer == 'new':
        pick = ctx.get('suggested') or 'something new'
        line = f"Bold choice. {pick} — coming right up."
        note = {'type': 'order_new', 'text': ctx.get('suggested', '')}
    elif answer == 'quest':
        qtext = (ctx.get('quest') or {}).get('text') or "today's quest"
        line  = f"That's the spirit. {qtext} — go on then."
        note  = {'type': 'quest_accept', 'text': qtext}
    else:
        return

    print(f'Kai (prompt reaction): {line}')
    _set_kai_state('speaking')
    speak(line)
    _set_kai_state('idle')

    _rtdb_patch(f'active_guests/{nfc_uid}',
                {'guestRequest': {**note, 'at': int(time.time() * 1000)}})
    return line


def _await_kai_prompt_answer(auth_uid: str, nfc_uid: str, ctx: dict):
    """Background poll for the app's tap-reply — cheap at this rate and
    avoids the Pi needing a persistent RTDB stream connection just for this."""
    def _do():
        deadline = time.time() + _PROMPT_ANSWER_TIMEOUT
        while time.time() < deadline:
            time.sleep(3)
            data = _rtdb_get(f'kai_prompts/{auth_uid}')
            if not data or data.get('status') != 'answered':
                continue
            reaction = _react_to_prompt_answer(nfc_uid, data.get('answer'), ctx)
            _rtdb_patch(f'kai_prompts/{auth_uid}', {
                'status':       'done',
                'reactionText': reaction,
                'doneAt':       int(time.time() * 1000),
            })
            return
        # Timed out — leave it pending; a late tap just won't get a spoken
        # reaction at the table, but the app still shows the card either way.
    threading.Thread(target=_do, daemon=True).start()


def run_conversation(nfc_uid: str, profile: dict,
                     auth_uid: str | None, memory_facts: list[str]):
    if not _conversation_lock.acquire(blocking=False):
        print('Conversation in progress — skipping')
        return

    try:
        # No dedicated "thinking" visual right now (simplified to idle/speaking
        # only, 2026-07-09) — stays idle while composing the greeting.
        order_ctx      = _load_order_context(auth_uid)
        greeting, ctx  = build_greeting(profile, memory_facts, order_ctx)
        guest_ctx      = _build_guest_ctx(profile, memory_facts, order_ctx)

        print(f'Kai: {greeting}')
        _set_kai_state('speaking')
        speak(greeting)

        if auth_uid:
            _push_kai_prompt(auth_uid, ctx)
            _await_kai_prompt_answer(auth_uid, nfc_uid, ctx)

        if not HAS_MIC or not OPENAI_AVAILABLE or not OPENAI_KEY:
            return   # greeting-only mode — no mic or no API key

        # Track full conversation for memory extraction + Firestore history
        api_messages  = [{'role': 'assistant', 'content': greeting}]
        store_messages = [{'role': 'assistant', 'content': greeting,
                           'timestamp': int(time.time() * 1000)}]

        for _ in range(MAX_TURNS):
            _set_kai_state('idle')   # listening for the guest — back to idle visual
            audio = _record_audio()
            if audio is None: print('Silence — ending'); break

            guest_text = _transcribe(audio)
            if not guest_text: print('Empty transcript — ending'); break

            print(f'Guest: {guest_text}')
            api_messages.append({'role': 'user', 'content': guest_text})

            # Stays idle while composing the reply (no dedicated "thinking" visual).
            reply = _kai_reply(api_messages, guest_ctx)
            if not reply: break

            print(f'Kai: {reply}')
            api_messages.append({'role': 'assistant', 'content': reply})
            store_messages.append({'role': 'user',      'content': guest_text,
                                   'timestamp': int(time.time() * 1000)})
            store_messages.append({'role': 'assistant', 'content': reply,
                                   'timestamp': int(time.time() * 1000)})

            _set_kai_state('speaking')
            speak(reply)

            # Extract memory after every exchange (fire-and-forget)
            if auth_uid:
                extract_and_save_memory(auth_uid, guest_text, reply)

        # Persist conversation history to Firestore
        if auth_uid and len(store_messages) > 1:
            save_conversation(auth_uid, store_messages)

    finally:
        _set_kai_state('idle')
        _conversation_lock.release()
        _reset_sleep_timer()


# ══════════════════════════════════════════════════════════════════════════════
#  NFC POLLING
# ══════════════════════════════════════════════════════════════════════════════

_last_tap: dict[str, float] = {}


def _is_staff_on_shift(auth_uid: str) -> tuple[bool, bool]:
    """
    Returns (is_staff, on_shift).

    is_staff comes from /staff_uids/{uid} — the RTDB mirror of Firestore
    users/{uid}.role, kept current by onUserRoleMirror (functions/index.js)
    the moment an admin toggles Staff on the console's App Users tab.

    on_shift comes from a SEPARATE, guest-toggled node — /staff_shift/{uid}
    .onShift — flipped by the staff member themselves in the app's Staff
    Panel. Deliberately not derived from role: plenty of staff accounts are
    off duty at any given moment, and a customer-facing table shouldn't
    switch into staff mode just because an off-shift staffer happened to
    have their coin in their pocket.
    """
    is_staff = bool(_rtdb_get(f'staff_uids/{auth_uid}'))
    shift = _rtdb_get(f'staff_shift/{auth_uid}') or {}
    on_shift = bool(shift.get('onShift'))
    return is_staff, on_shift


_STAFF_PROMPT_ANSWER_TIMEOUT = 60  # shorter than the guest recommendation
                                    # window (kai_prompts) — staff are
                                    # expected to have their phone right there


def _push_staff_prompt(auth_uid: str, table: dict):
    """Ask 'Close Table X?' in the staff member's own app instead of closing
    on the spot — same relay pattern as kai_prompts (this file's guest-
    facing sibling), just a different RTDB node so the two never collide."""
    _rtdb_put(f'staff_prompts/{auth_uid}', {
        'status':     'pending',
        'type':       'close_table',
        'question':   f'Close {TABLE_NAME}?',
        'tableId':    TABLE_ID,
        'tableName':  TABLE_NAME,
        'guestName':  table.get('guestName', ''),
        'createdAt':  int(time.time() * 1000),
        'answer':     None,
        'answeredAt': None,
    })


def _await_staff_prompt_answer(auth_uid: str, staff_name: str):
    """Background poll for the staff app's Yes/No tap. On 'yes', performs
    the actual close via _do_close_table — the same logic the legacy
    instant-close badge path uses — and speaks the same confirmation line
    at the table. Never auto-closes on a timeout: silence isn't consent."""
    def _do():
        deadline = time.time() + _STAFF_PROMPT_ANSWER_TIMEOUT
        while time.time() < deadline:
            time.sleep(2)
            data = _rtdb_get(f'staff_prompts/{auth_uid}')
            if not data or data.get('status') != 'answered':
                continue
            answer = data.get('answer')
            if answer == 'yes':
                result = _do_close_table(auth_uid)
                if result:
                    print(f"{staff_name} confirmed close on {TABLE_NAME} via app — "
                          f"guest {result['occName']}, total {result['total']} BHD")
                    _set_kai_state('speaking')
                    speak('Table cleared. Until next time.')
                    _set_kai_state('idle')
                    reaction = 'Table cleared.'
                else:
                    reaction = 'Already clear by the time you confirmed.'
            else:
                print(f'{staff_name} declined to close {TABLE_NAME}')
                reaction = 'Left open.'
            _rtdb_patch(f'staff_prompts/{auth_uid}', {
                'status':       'done',
                'reactionText': reaction,
                'doneAt':       int(time.time() * 1000),
            })
            return
        # Timed out — no answer. Table stays open; staff can tap again or
        # use the console's own close button.
    threading.Thread(target=_do, daemon=True).start()


def _handle_tap(nfc_uid: str):
    now = time.time()
    if nfc_uid in _last_tap and (now - _last_tap[nfc_uid]) < DEBOUNCE_SECS:
        return
    _last_tap[nfc_uid] = now

    display_wake()
    # No dedicated "attention" visual right now — stays idle until speaking starts.
    _cancel_nudge()   # guest tapped again — no need to nudge

    print(f'\nNFC tap — UID: {nfc_uid}  ({TABLE_NAME})')

    # Staff tap? → close / free this table instead of seating a guest.
    # Two systems here, oldest-first:
    #  1. LEGACY: badge registered via the console's Staff Assignments modal
    #     (/staff_badges/{nfc_uid}) — no linked app account to send a
    #     confirmation to, so this still closes instantly like it always has.
    #  2. NEW: badge self-linked via the Kingdom app (Staff Panel → Link My
    #     Badge, reusing the same NfcLinkScreen customers use) to a
    #     users/{uid}.role=='staff' account that's toggled ON SHIFT in the
    #     app — this asks "Close Table X?" in THEIR app instead of closing
    #     on the spot.
    staff = lookup_staff(nfc_uid)
    if staff:
        print(f'Staff tap (legacy badge) — {staff.get("name", "staff")} closing {TABLE_NAME}')
        close_table(nfc_uid, staff.get('name', 'staff'))
        _set_kai_state('idle')
        return

    # Resolve identity — reused below for the guest flow too if this isn't
    # (or isn't currently on-shift as) staff.
    auth_uid = lookup_auth_uid(nfc_uid)

    if auth_uid:
        is_staff, on_shift = _is_staff_on_shift(auth_uid)
        if is_staff:
            if not on_shift:
                print(f'Staff tap ({auth_uid}) — off shift, ignoring table action')
                speak("You're off shift — toggle on shift in the app first.")
                _set_kai_state('idle')
                return
            table = _rtdb_get(f'tables/{TABLE_ID}') or {}
            if not table.get('arrivedAt'):
                print(f'Staff tap ({auth_uid}) — {TABLE_NAME} already free')
                speak('This table is already clear.')
                _set_kai_state('idle')
                return
            staff_profile = _rtdb_get(f'users/{auth_uid}/profile') or {}
            staff_name = staff_profile.get('username') or staff_profile.get('name') or 'staff'
            print(f'Staff tap ({staff_name}) — asking to close {TABLE_NAME} via app')
            _push_staff_prompt(auth_uid, table)
            _await_staff_prompt_answer(auth_uid, staff_name)
            speak('Check your phone to confirm.')
            _set_kai_state('idle')
            return

    # Update profile
    if auth_uid:
        profile = upsert_linked_customer(auth_uid, nfc_uid)
        memory_facts = load_kai_memory(auth_uid)
        print(f'{len(memory_facts)} memory fact(s) loaded')
    else:
        profile      = upsert_guest(nfc_uid)
        memory_facts = []
        print('No linked account — using guest profile')

    write_checkin(auth_uid, nfc_uid, profile)

    threading.Thread(
        target=run_conversation,
        args=(nfc_uid, profile, auth_uid, memory_facts),
        daemon=True,
    ).start()


def _poll_loop():
    prev_uid = [None]
    last_err = [None]   # dedupe: only print when the error actually changes,
                         # since "no card present" throws every idle cycle
    while True:
        try:
            available = readers()
            if not available:
                time.sleep(2); continue
            try:
                conn = available[0].createConnection()
                # ACR122U beeps the instant it senses a card in the RF field,
                # but pcscd's own connect handshake — and even a successful
                # connect's first GET_UID — can lag behind a real human
                # tap-and-pull motion (typically ~300-600ms of actual dwell
                # time on the reader). The original version here only
                # retried connect() and gave up on the read after a single
                # transmit; in practice that showed up on real hardware as
                # alternating "No smart card inserted" (lost the race on
                # connect) AND "GET_UID returned sw1=0x63" (connected fine,
                # but the read landed on a half-seated card) — both are the
                # same underlying "still mid-tap" problem, so both now retry
                # through the SAME loop rather than only the first failure
                # mode. Up to 8 attempts × 80ms ≈ 640ms covers a real tap;
                # a solid contact still resolves in 1 attempt with no added
                # latency, and a genuinely empty reader still fails at
                # roughly the old idle-poll cost.
                uid = None
                sw1 = None
                last_exc = None
                for _attempt in range(8):
                    try:
                        conn.connect()
                    except Exception as ce:
                        last_exc = ce
                        time.sleep(0.08)
                        continue
                    try:
                        data, sw1, _ = conn.transmit(GET_UID)
                    except Exception as te:
                        last_exc = te
                        try:
                            conn.disconnect()
                        except Exception:
                            pass
                        time.sleep(0.08)
                        continue
                    if sw1 == 0x90:
                        uid = toHexString(data).replace(' ', '').lower()
                        last_exc = None
                        break
                    # sw1 != 0x90 (e.g. 0x63) — connected but a bad read on
                    # an otherwise-present card. Disconnect and retry fresh
                    # rather than waiting a full poll cycle, since the card
                    # is very likely still there right now.
                    last_exc = None
                    try:
                        conn.disconnect()
                    except Exception:
                        pass
                    time.sleep(0.08)

                try:
                    conn.disconnect()
                except Exception:
                    pass

                if uid:
                    if uid != prev_uid[0]:
                        prev_uid[0] = uid
                        _handle_tap(uid)
                    last_err[0] = None
                elif last_exc:
                    raise last_exc
                else:
                    msg = f'GET_UID returned sw1={sw1:#x} (expected 0x90)'
                    if msg != last_err[0]:
                        print(f'Card read: {msg}')
                        last_err[0] = msg
            except Exception as e:
                prev_uid[0] = None
                msg = f'{type(e).__name__}: {e}'
                if msg != last_err[0]:
                    print(f'Card connect/transmit error: {msg}')
                    last_err[0] = msg
        except Exception as e:
            print(f'Poll error: {e}')
        time.sleep(0.2)


# ══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════════════════

def main():
    if not SMARTCARD_AVAILABLE:
        print('pyscard required: pip install pyscard')
        sys.exit(1)
    if not readers():
        print('No NFC reader found — is the ACR122U plugged in?')
        sys.exit(1)

    print(f'NFC reader: {readers()[0]}')
    print(f'Station: {TABLE_NAME} (ID: {TABLE_ID})')
    print(f'Display: {"enabled (DISPLAY=" + _DISPLAY + ")" if HAS_DISPLAY else "none"}')
    print(f'Mic:     {"detected" if HAS_MIC else "not found — greeting only, no conversation"}')
    print(f'Sleep after {SLEEP_TIMEOUT}s idle')
    display_sleep()   # start asleep
    _set_kai_state('idle')   # kai_screen.py also starts on idle by default; this is just explicit

    print('Kai is watching. Tap a badge to wake.\n')

    # Prime the menu cache at startup so the first conversation doesn't wait
    print('Loading menu from Tavern RTDB…')
    fetch_menu_context()

    signal.signal(signal.SIGINT,  lambda s, f: sys.exit(0))
    signal.signal(signal.SIGTERM, lambda s, f: sys.exit(0))

    _poll_loop()


if __name__ == '__main__':
    main()
