#!/usr/bin/env python3
"""
check_dart_syntax.py — a dependency-free Dart syntax gate.

Why this exists: `flutter analyze` needs the SDK + pub deps, which isn't always
available (CI sandbox, no toolchain, offline). This parses Dart well enough to
catch the failures that actually bite during heavy editing:

  • unbalanced (), [], {}
  • unterminated string literals
  • damage from a truncated / half-written file

It is Dart-aware: it skips // and /* nested */ comments, understands '', "",
''' ''', \"\"\" \"\"\", raw strings (r'...'), escapes, and ${...} interpolation
(including nested braces and quotes inside the interpolation).

Usage:
    python scripts/check_dart_syntax.py lib/**/*.dart
    python scripts/check_dart_syntax.py            # defaults to all of lib/

Exit code is non-zero if any file fails, so it works as a pre-commit hook.

NOTE (hard-won): when reading these files through a synced/virtual mount, a read
can return a STALE, TRUNCATED view of a file that was just written. If a file
here looks truncated but is fine on disk, let the mount settle and re-run rather
than "fixing" (and thereby truncating) the real file.
"""
import sys
import glob


def check(path):
    try:
        s = open(path, encoding='utf-8').read()
    except Exception as e:  # unreadable == worth reporting
        return f"{path}: cannot read ({e})"

    if '\0' in s:
        return f"{path}: contains NUL bytes (file is corrupt)"

    i, n = 0, len(s)
    stack = []
    line = 1

    def err(msg):
        return f"{path}:{line}: {msg}"

    while i < n:
        c = s[i]
        if c == '\n':
            line += 1
            i += 1
            continue

        # ── comments ──────────────────────────────────────────────────────
        if c == '/' and i + 1 < n:
            if s[i + 1] == '/':
                while i < n and s[i] != '\n':
                    i += 1
                continue
            if s[i + 1] == '*':
                i += 2
                depth = 1
                while i < n and depth:
                    if s[i] == '\n':
                        line += 1
                    if s.startswith('/*', i):
                        depth += 1
                        i += 2
                        continue
                    if s.startswith('*/', i):
                        depth -= 1
                        i += 2
                        continue
                    i += 1
                continue

        # ── strings ───────────────────────────────────────────────────────
        if c in '\'"' or (c == 'r' and i + 1 < n and s[i + 1] in '\'"'):
            raw = (c == 'r')
            if raw:
                i += 1
            q = s[i]
            triple = s.startswith(q * 3, i)
            delim = q * 3 if triple else q
            start_line = line
            i += len(delim)
            closed = False
            while i < n:
                if s[i] == '\n':
                    line += 1
                    if not triple:
                        return err(f"unterminated string (opened line {start_line})")
                    i += 1
                    continue
                if not raw and s[i] == '\\':
                    i += 2
                    continue
                if not raw and s.startswith('${', i):
                    i += 2
                    d = 1
                    while i < n and d:
                        if s[i] == '\n':
                            line += 1
                        elif s[i] == '{':
                            d += 1
                        elif s[i] == '}':
                            d -= 1
                        elif s[i] in '\'"':
                            iq = s[i]
                            i += 1
                            while i < n and s[i] != iq:
                                if s[i] == '\\':
                                    i += 1
                                if s[i] == '\n':
                                    line += 1
                                i += 1
                        i += 1
                    continue
                if s.startswith(delim, i):
                    i += len(delim)
                    closed = True
                    break
                i += 1
            if not closed:
                return err(f"unterminated string (opened line {start_line})")
            continue

        # ── delimiters ────────────────────────────────────────────────────
        if c in '([{':
            stack.append((c, line))
            i += 1
            continue
        if c in ')]}':
            if not stack:
                return err(f"unexpected closing '{c}'")
            o, ol = stack.pop()
            if '([{'.index(o) != ')]}'.index(c):
                return err(f"mismatched '{c}' closing '{o}' from line {ol}")
            i += 1
            continue
        i += 1

    if stack:
        o, ol = stack[-1]
        return f"{path}: UNCLOSED '{o}' opened at line {ol} (file may be truncated)"
    return None


def main():
    paths = sys.argv[1:] or glob.glob('lib/**/*.dart', recursive=True)
    paths = [p for p in paths if not p.split('/')[-1].startswith('.')]
    bad = 0
    for p in sorted(paths):
        r = check(p)
        if r:
            bad += 1
            print("FAIL " + r)
    print(f"\nchecked {len(paths)} file(s); {bad} with syntax problems")
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
