#!/usr/bin/env python3
"""
kai_screen.py — drives Kai's face display.

Screen hardware note (2026-07-09, confirmed live): this is the original 3.5"
26-pin SPI screen (ILI9486 controller, ADS7846/XPT2046-family touch),
brought up via `dtoverlay=piscreen,speed=16000000,rotate=90` in
/boot/firmware/config.txt. A DSI panel (DFRobot DFR0550) was investigated
as a possible alternative earlier and left unresolved — this SPI screen is
the one actually working, so it's the target now. Interestingly `piscreen`
registers it as the PRIMARY framebuffer (/dev/fb0), not a secondary
/dev/fb1 as fbtft screens usually appear — confirmed via
`fbset -fb /dev/fb0`:
    mode "480x320", geometry 480 320 480 320 16, rgba 5/11,6/5,5/0,0/0
That's 480x320 @ 16bpp RGB565 (5-bit R at bit 11, 6-bit G at bit 5, 5-bit B
at bit 0) — exactly what FB_PIXFMT='rgb565le' below produces.

Runs Kai's full wake state machine, but instead of pre-rendered mp4 clips
(the old approach — see git history / kai_screen_mp4_version.py if you kept
a copy), this plays raw PNG frame sequences directly, the same "frames"
approach the Flutter app's kai_avatar.dart already uses. Every frame is
decoded and packed to the screen's raw pixel format once at startup, then
played back by blitting straight into the framebuffer — no ffmpeg process
per clip, no re-encoding step, no build_clips.sh. Smoother playback (no
decoder startup/stutter at every transition) and adding a new state later
is just "drop a new folder of zero-padded frame_XXXX.png files in" instead
of re-running a build script.

    idle --[idle_to_speaking]--> speaking
      ^                              |
      +-------[speaking_to_idle]-----+

Simplified to 2 states (2026-07-09) for NFC/audio testing — attention and
thinking are parked, not removed from the concept, just not wired up right
now. Each state has a looping frame folder (idle/, speaking/) that plays
continuously while Kai is in that state, and each edge has a one-shot
transition frame folder that plays once when moving to the next state.
nfc_listener.py drives the state machine by writing the
*target* state name into /tmp/kai_state; this script does the rest (playing
the correct transition, then settling into the target's loop).

Frame folders are expected to contain zero-padded, lexicographically-sortable
PNGs (frame_0000.png, frame_0001.png, ...) — exactly the naming convention
already used for the existing idle/attention/thinking/speaking frame exports.

Requires: Pillow and numpy (`pip install pillow numpy` — numpy is only used
to vectorize the one-time RGB→framebuffer pixel-format packing at startup,
not in the per-frame playback loop, so it isn't a runtime hot path).

Before running:
  1. Drop each state's/edge's frame folder under MEDIA_DIR (see LOOP_DIRS /
     TRANSITION_DIRS below for the exact folder names expected).
  2. Confirm your screen's resolution/bit depth via `fbset -fb /dev/fb0`
     and adjust the env vars below if they differ from the defaults.
"""
import glob
import os
import signal
import sys
import threading
import time

from PIL import Image
import numpy as np

# ---- Config -------------------------------------------------------------
MEDIA_DIR = os.environ.get(
    'KAI_MEDIA_DIR', '/home/kai/tavern_station/media/frames'
)
FB_DEVICE = os.environ.get('KAI_FB_DEVICE', '/dev/fb0')
FB_WIDTH  = int(os.environ.get('KAI_FB_WIDTH', '480'))
FB_HEIGHT = int(os.environ.get('KAI_FB_HEIGHT', '320'))
# Confirmed live via `fbset -fb /dev/fb0` (see docstring above) — 16bpp
# RGB565, R high/B low, which is exactly what 'rgb565le' packs.
FB_PIXFMT = os.environ.get('KAI_FB_PIXFMT', 'rgb565le')
FPS       = int(os.environ.get('KAI_FPS', '24'))
STATE_FILE = os.environ.get('KAI_STATE_FILE', '/tmp/kai_state')
POLL_SECS  = 0.1

# Looping frame folder for each steady state (subfolder name under MEDIA_DIR).
LOOP_DIRS = {
    'idle':      'idle',
    'speaking':  'speaking',
}
# One-shot transition frame folder for each (from_state, to_state) edge.
# Simplified (2026-07-09) to just idle <-> speaking for NFC/audio testing —
# attention/thinking are parked, not deleted; see git history if reviving
# the 4-state cycle. idle_to_speaking has no frame folder yet, so that edge
# hard-cuts until frames are added (see _play_transition_blocking below) —
# that's expected right now, not a bug.
TRANSITION_DIRS = {
    ('idle', 'speaking'):  'idle_to_speaking',
    ('speaking', 'idle'):  'speaking_to_idle',
}
VALID_STATES = set(LOOP_DIRS)

# ---- Framebuffer I/O ------------------------------------------------------
_fb = None  # opened once in main(), kept open for the process lifetime


def _dir(name: str) -> str:
    return os.path.join(MEDIA_DIR, name)


def _pack_frame(im: Image.Image) -> bytes:
    """Convert a PIL image to raw bytes in FB_PIXFMT, sized to the screen."""
    im = im.convert('RGB').resize((FB_WIDTH, FB_HEIGHT))
    arr = np.asarray(im, dtype=np.uint16)  # H x W x 3 (R,G,B)

    if FB_PIXFMT in ('rgb565le', 'bgr565le'):
        r = arr[:, :, 0] >> 3  # 5 bits
        g = arr[:, :, 1] >> 2  # 6 bits
        b = arr[:, :, 2] >> 3  # 5 bits
        if FB_PIXFMT == 'bgr565le':
            packed = (b << 11) | (g << 5) | r
        else:
            packed = (r << 11) | (g << 5) | b
        return packed.astype('<u2').tobytes()

    arr8 = arr.astype(np.uint8)
    if FB_PIXFMT == 'bgr24':
        return arr8[:, :, ::-1].tobytes()
    if FB_PIXFMT in ('bgra', 'rgba'):
        rgba = np.dstack([arr8, np.full(arr8.shape[:2], 255, dtype=np.uint8)])
        if FB_PIXFMT == 'bgra':
            rgba = rgba[:, :, [2, 1, 0, 3]]
        return rgba.tobytes()

    raise ValueError(f'Unsupported KAI_FB_PIXFMT: {FB_PIXFMT}')


def _write_frame(raw: bytes):
    try:
        _fb.seek(0)
        _fb.write(raw)
        _fb.flush()
    except OSError as e:
        print(f'⚠️  Framebuffer write failed: {e}')


# ---- Frame cache ------------------------------------------------------------
_frame_cache: dict[str, list[bytes]] = {}  # dir name -> packed frames


def _load_frames(dir_name: str) -> list:
    if dir_name in _frame_cache:
        return _frame_cache[dir_name]
    paths = sorted(glob.glob(os.path.join(_dir(dir_name), '*.png')))
    frames = [_pack_frame(Image.open(p)) for p in paths]
    _frame_cache[dir_name] = frames
    return frames


def _preload_all():
    """Decode + pack every loop and transition folder once at startup."""
    all_dirs = list(LOOP_DIRS.values()) + list(TRANSITION_DIRS.values())
    for d in all_dirs:
        n = len(_load_frames(d))
        print(f'    loaded {n:>4} frames — {d}')


# ---- Playback ---------------------------------------------------------------
class LoopPlayer(threading.Thread):
    """Continuously loops a state's frames, writing each to the framebuffer,
    until .stop() is called. Runs in its own thread so the main loop can
    keep polling STATE_FILE while a loop plays."""

    def __init__(self, frames: list, fps: int):
        super().__init__(daemon=True)
        self._frames = frames
        self._interval = 1.0 / fps if fps > 0 else 0
        self._stop_evt = threading.Event()

    def run(self):
        if not self._frames:
            return
        i, n = 0, len(self._frames)
        while not self._stop_evt.is_set():
            t0 = time.monotonic()
            _write_frame(self._frames[i])
            i = (i + 1) % n
            dt = self._interval - (time.monotonic() - t0)
            if dt > 0:
                self._stop_evt.wait(dt)

    def stop(self):
        self._stop_evt.set()
        self.join(timeout=2)


def _play_loop(state: str) -> LoopPlayer:
    """Start the looping frames for `state` as a background thread."""
    frames = _frame_cache.get(LOOP_DIRS[state], [])
    player = LoopPlayer(frames, FPS)
    player.start()
    return player


def _stop(player: LoopPlayer):
    if player:
        player.stop()


def _play_transition_blocking(from_state: str, to_state: str) -> bool:
    """
    Play the one-shot transition frames for from_state -> to_state, if any
    exist, and block until done. Returns True if a transition was played,
    False if there's no defined edge (caller should hard-cut).
    """
    dir_name = TRANSITION_DIRS.get((from_state, to_state))
    if not dir_name:
        return False
    frames = _frame_cache.get(dir_name, [])
    if not frames:
        print(f'⚠️  Missing/empty transition frames in {_dir(dir_name)}, hard-cutting instead')
        return False
    interval = 1.0 / FPS if FPS > 0 else 0
    for f in frames:
        t0 = time.monotonic()
        _write_frame(f)
        dt = interval - (time.monotonic() - t0)
        if dt > 0:
            time.sleep(dt)
    return True


# ---- State file -------------------------------------------------------------
def read_target_state() -> str:
    try:
        with open(STATE_FILE) as f:
            state = f.read().strip().lower()
    except FileNotFoundError:
        return 'idle'
    return state if state in VALID_STATES else 'idle'


# ---- Startup checks -----------------------------------------------------------
def _check_assets():
    """
    Only the framebuffer device is a hard requirement — without it there's
    nothing to run for. Missing/empty frame folders (loops or transitions)
    are just warned about, not fatal: LoopPlayer no-ops on an empty frame
    list (screen just stays blank/on the last frame for that state) and
    _play_transition_blocking() already falls back to a hard cut when a
    transition folder is missing. This is deliberate — it's what lets you
    ship with only some states/edges built and add the rest later (e.g.
    'attention' and all 4 transitions, as of writing) without touching
    this function again.
    """
    missing_loops = []
    for state, name in LOOP_DIRS.items():
        d = _dir(name)
        if not os.path.isdir(d) or not glob.glob(os.path.join(d, '*.png')):
            missing_loops.append((state, d))
    missing_transitions = []
    for edge, name in TRANSITION_DIRS.items():
        d = _dir(name)
        if not os.path.isdir(d) or not glob.glob(os.path.join(d, '*.png')):
            missing_transitions.append((edge, d))

    if missing_loops:
        print('⚠️  Missing/empty state loop(s) — that state will show a blank/frozen screen until frames are added:')
        for state, d in missing_loops:
            print(f'    {state:<10} {d}')
    if missing_transitions:
        print('⚠️  Missing/empty transition(s) — those edges will hard-cut instead of animating:')
        for edge, d in missing_transitions:
            print(f'    {edge[0]} -> {edge[1]:<10} {d}')
    if missing_loops or missing_transitions:
        print('   Each folder must contain zero-padded frame_0001.png, frame_0002.png, ...\n')

    if not os.path.exists(FB_DEVICE):
        print(f'❌ Framebuffer not found: {FB_DEVICE}')
        print('   Screen driver not installed yet? See SETUP.md.')
        sys.exit(1)


def main():
    global _fb
    _check_assets()
    print(f'🖼️  Kai screen controller on {FB_DEVICE} ({FB_WIDTH}x{FB_HEIGHT}, {FB_PIXFMT}, {FPS}fps)')
    print(f'    media dir: {MEDIA_DIR}')
    print(f'    watching:  {STATE_FILE}')
    print('    preloading frames…')
    _preload_all()

    _fb = open(FB_DEVICE, 'r+b', buffering=0)

    current_state = 'idle'
    player = _play_loop(current_state)
    print(f'    state: idle (looping)\n')

    def shutdown(*_):
        print('\n🛑 Stopping Kai screen controller…')
        _stop(player)
        try:
            _fb.close()
        except Exception:
            pass
        sys.exit(0)

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    try:
        while True:
            target = read_target_state()
            if target != current_state:
                _stop(player)
                played = _play_transition_blocking(current_state, target)
                if not played:
                    print(f'➡️  {current_state} -> {target} (hard cut, no transition defined)')
                else:
                    print(f'➡️  {current_state} -> {target} (via transition)')
                player = _play_loop(target)
                current_state = target
            elif not player.is_alive():
                # Loop thread died unexpectedly — restart the same loop.
                player = _play_loop(current_state)
            time.sleep(POLL_SECS)
    finally:
        _stop(player)


if __name__ == '__main__':
    main()
