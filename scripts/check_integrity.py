#!/usr/bin/env python3
"""Fast source-integrity check — catches file corruption BEFORE a build.

Scans lib/ for the two failure modes we've actually seen:
  1. NUL bytes embedded in a Dart source file (partial/racy writes).
  2. A .dart file that doesn't end on a closing brace '}' (truncation).

Run it before `flutter run`:  python scripts/check_integrity.py
Exit code 0 = clean, 1 = problems found (prints the offending files).
"""
import os
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..", "lib")
problems = []
checked = 0

for dirpath, _dirs, files in os.walk(ROOT):
    for name in files:
        if not name.endswith(".dart"):
            continue
        path = os.path.join(dirpath, name)
        rel = os.path.relpath(path, os.path.join(ROOT, ".."))
        try:
            data = open(path, "rb").read()
        except Exception as e:  # noqa
            problems.append(f"{rel}: unreadable ({e})")
            continue
        checked += 1
        if b"\x00" in data:
            problems.append(f"{rel}: contains {data.count(0)} NUL byte(s) — corrupt")
        stripped = data.rstrip()
        if stripped and not stripped.endswith(b"}"):
            tail = stripped[-40:].decode("utf-8", "replace").replace("\n", " ")
            problems.append(f"{rel}: does not end in '}}' — likely truncated (…{tail})")

if problems:
    print(f"INTEGRITY: {len(problems)} problem(s) in {checked} files:")
    for p in problems:
        print("  ✗ " + p)
    sys.exit(1)

print(f"INTEGRITY: OK — {checked} Dart files clean (no NULs, all end correctly).")
sys.exit(0)
