#!/usr/bin/env python3
"""
kai_screen_preview.py — desktop-window version of kai_screen.py, for testing
over VNC.

kai_screen.py writes raw bytes straight into /dev/fb0 — it bypasses the
desktop entirely, which means it's invisible to VNC (VNC screen-shares the
desktop compositor's output, a completely different buffer from the raw
framebuffer device once the DSI screen and its driver are sorted out). This
script plays the exact same state machine — same LOOP_DIRS/TRANSITION_DIRS,
same /tmp/kai_state file — but draws into a normal Tkinter window instead,
so it's visible over VNC right now, with or without the physical screen
working.

Two ways to drive it:
  1. Run nfc_listener.py alongside it (real flow) — this window reacts to
     the exact same state writes the physical screen would.
  2. Press 1/2 in this window to jump straight to idle/speaking for a
     quick look, no NFC tap needed.

Run on the Pi over VNC (needs a desktop session, so run it from a terminal
INSIDE the VNC session, not over plain SSH):

    cd ~/tavern_station   # wherever kai_screen.py's MEDIA_DIR points
    python3 kai_screen_preview.py

Requires: Pillow, python3-tk (pip install pillow; apt install python3-tk).
"""
import glob
import os
import sys
import tkinter as tk

from PIL import Image, ImageTk

MEDIA_DIR = os.environ.get(
    'KAI_MEDIA_DIR', '/home/kai/tavern_station/media/frames'
)
STATE_FILE = os.environ.get('KAI_STATE_FILE', '/tmp/kai_state')
WIN_SIZE = int(os.environ.get('KAI_PREVIEW_SIZE', '400'))
FPS = int(os.environ.get('KAI_FPS', '24'))
POLL_MS = 100

LOOP_DIRS = {
    'idle':      'idle',
    'speaking':  'speaking',
}
TRANSITION_DIRS = {
    ('idle', 'speaking'):  'idle_to_speaking',
    ('speaking', 'idle'):  'speaking_to_idle',
}
VALID_STATES = set(LOOP_DIRS)
KEY_STATES = {'1': 'idle', '2': 'speaking'}


def _dir(name: str) -> str:
    return os.path.join(MEDIA_DIR, name)


def _load(dir_name: str, tk_root) -> list:
    paths = sorted(glob.glob(os.path.join(_dir(dir_name), '*.png')))
    frames = []
    for p in paths:
        im = Image.open(p).convert('RGB').resize((WIN_SIZE, WIN_SIZE))
        frames.append(ImageTk.PhotoImage(im, master=tk_root))
    return frames


class Preview:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title('Kai — screen preview (VNC test)')
        self.root.configure(bg='black')

        self.label = tk.Label(self.root, bg='black')
        self.label.pack()

        self.status = tk.Label(
            self.root, bg='black', fg='#888', anchor='w',
            text='1=idle 2=speaking — or drive via nfc_listener.py',
        )
        self.status.pack(fill='x')

        self.root.bind('<Key>', self._on_key)

        print('Loading frames…')
        self.loops = {s: _load(d, self.root) for s, d in LOOP_DIRS.items()}
        self.transitions = {e: _load(d, self.root) for e, d in TRANSITION_DIRS.items()}
        for s, frames in self.loops.items():
            print(f'  {s:<10} {len(frames)} frames')

        self.current_state = 'idle'
        self.frame_i = 0
        self.playing_transition = None  # (frames, index) while a transition is running

        if not os.path.exists(STATE_FILE):
            with open(STATE_FILE, 'w') as f:
                f.write('idle')

        self._tick()
        self._poll_state()
        self.root.mainloop()

    def _on_key(self, event):
        target = KEY_STATES.get(event.char)
        if target:
            with open(STATE_FILE, 'w') as f:
                f.write(target)

    def _poll_state(self):
        try:
            with open(STATE_FILE) as f:
                target = f.read().strip().lower()
        except FileNotFoundError:
            target = 'idle'
        if target not in VALID_STATES:
            target = 'idle'

        if target != self.current_state and self.playing_transition is None:
            edge = (self.current_state, target)
            tframes = self.transitions.get(edge)
            if tframes:
                self.status.config(text=f'{self.current_state} -> {target}  (transition)')
                self.playing_transition = [tframes, 0, target]
            else:
                self.status.config(text=f'{self.current_state} -> {target}  (hard cut, no edge)')
                self.current_state = target
                self.frame_i = 0

        self.root.after(POLL_MS, self._poll_state)

    def _tick(self):
        if self.playing_transition:
            frames, i, target = self.playing_transition
            if i < len(frames):
                self.label.configure(image=frames[i])
                self.playing_transition[1] += 1
            else:
                self.current_state = target
                self.frame_i = 0
                self.playing_transition = None
                self.status.config(text=f'state: {self.current_state} (looping) — 1/2 to switch')
        else:
            frames = self.loops.get(self.current_state, [])
            if frames:
                self.label.configure(image=frames[self.frame_i % len(frames)])
                self.frame_i += 1
            if self.status.cget('text').startswith('state:') is False and self.playing_transition is None:
                pass

        self.root.after(int(1000 / FPS), self._tick)


if __name__ == '__main__':
    if not os.path.isdir(MEDIA_DIR):
        print(f'No frames found at {MEDIA_DIR} — set KAI_MEDIA_DIR to point at the frames folder.')
        sys.exit(1)
    Preview()
