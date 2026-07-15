#!/usr/bin/env python3
"""Fast source-integrity check — catches file corruption BEFORE a build.

Scans lib/ for the two failure modes we've actually seen:
  1. NUL bytes embedded in a Dart source file (partial/racy writes) — always bad.
  2. A .dart file that ends mid-token (truncation). A healthy Dart file ends on
     a real terminator: '}', ';', or ')'. Anything else (a letter, an operator,
     an open bracket) means the tail was cut off.

Run it before `flutter run`:  python scripts/check_integrity.py
Exit 0 = clean, 1 = problems found (prints the offending files + their tail).
"""
import os
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..", "lib")
TERMINATORS = (ord("}"), ord(";"), ord(")"))
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
        if stripped and stripped[-1] not in TERMINATORS:
            tail = stripped[-44:].decode("utf-8", "replace").replace("\n", " ")
            problems.append(f"{rel}: ends mid-token — likely truncated (…{tail})")

if problems:
    print(f"INTEGRITY: {len(problems)} problem(s) in {checked} files:")
    for p in problems:
        print("  x " + p)
    sys.exit(1)

print(f"INTEGRITY: OK — {checked} Dart files clean.")
sys.exit(0)
