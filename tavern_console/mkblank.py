#!/usr/bin/env python3
"""Generate the privacy-scrubbed distributable (tavern_console_blank.html) from
the reference build (tavern_console.html).

The reference embeds three real-data literals. The blank replaces each with the
empty/neutral version (copied verbatim from the previous blank so the scrub is
identical to what was already privacy-audited). Everything else — all the app
code — is carried across untouched.

Scrubbed literals:
  const DATA={...}                real ingredients / menu / suppliers
  DATA.week=DATA.week||{...}      real venue, sales, employees (incl. names)
  let POS={...}                   real till export

Run from the tavern_console folder:  python3 mkblank.py
"""
import sys, os

REF   = 'tavern_console.html'
BLANK = 'tavern_console_blank.html'

def brace_span(s, open_idx):
    """Return (start, end) of the {...} or [...] literal beginning at open_idx,
    respecting quoted strings so a brace inside a value never miscounts."""
    openc = s[open_idx]
    closec = '}' if openc == '{' else ']'
    depth = 0
    k = open_idx
    instr = False
    esc = False
    q = ''
    while k < len(s):
        c = s[k]
        if instr:
            if esc:
                esc = False
            elif c == '\\':
                esc = True
            elif c == q:
                instr = False
        else:
            if c == '"' or c == "'":
                instr = True; q = c
            elif c == openc:
                depth += 1
            elif c == closec:
                depth -= 1
                if depth == 0:
                    return open_idx, k
        k += 1
    raise ValueError('unbalanced literal from index %d' % open_idx)

def literal(s, marker, opener):
    i = s.find(marker)
    if i < 0:
        raise ValueError('marker not found: ' + marker)
    j = s.index(opener, i)
    a, b = brace_span(s, j)
    return a, b, s[a:b + 1]

# (marker before the literal, the opening bracket char)
SPECS = [
    ('const DATA=',            '{'),
    ('DATA.week=DATA.week||',  '{'),
    ('let POS=',               '{'),
]

# Plain-text genericisations: strip the venue name from the title, header and
# storage key so the distributable carries no branding. Each must apply exactly
# once.
# Brand: Hoard.
TEXT_SUBS = [
    ('<title>The Tavern — Costing Console</title>', '<title>Hoard</title>'),
    ('\U0001f37d THE TAVERN — Costing Console',      '◆ Hoard'),
    ("const KEY='tavern-unified-v1'",                     "const KEY='hoard-v1'"),
]

# The cloud/platform build. mkblank writes the offline blank (used by the tests
# and as the offline distributable) AND, if a config is set here, a second file
# public/index.html with that config baked in — the deployable platform build.
# Keeping the config out of the offline blank is what lets the test suite keep
# running the app instead of the sign-in screen.
EMPTY_CONFIG = "const CLOUD_CONFIG={apiKey:'',authDomain:'',projectId:'',storageBucket:'',appId:''};"
CLOUD_CONFIG_FILL = (
    "const CLOUD_CONFIG={"
    "apiKey:'AIzaSyCAkQDVYaKwdMSjSD_3UuxgKMe_kp1Jw3A',"
    "authDomain:'hoard-ac666.firebaseapp.com',"
    "projectId:'hoard-ac666',"
    "storageBucket:'hoard-ac666.firebasestorage.app',"
    "appId:'1:783911286552:web:97306fc1d397312b4e106d'};"
)

def main():
    if not (os.path.exists(REF) and os.path.exists(BLANK)):
        sys.exit('run from the tavern_console folder (need %s and %s)' % (REF, BLANK))
    ref = open(REF, encoding='utf-8').read()
    blank = open(BLANK, encoding='utf-8').read()

    out = ref
    for marker, opener in SPECS:
        _, _, empty_val = literal(blank, marker, opener)   # neutral version
        a, b, _ = literal(out, marker, opener)             # real version in ref
        out = out[:a] + empty_val + out[b + 1:]

    for find, repl in TEXT_SUBS:
        n = out.count(find)
        if n != 1:
            sys.exit('TEXT_SUB expected exactly 1 occurrence, found %d: %r' % (n, find[:40]))
        out = out.replace(find, repl)

    open(BLANK, 'w', encoding='utf-8').write(out)

    low = out.lower()
    hits = {t: low.count(t) for t in ('tavern', 'rawad', 'sk-ant')}
    total = sum(hits.values())
    print('blank rebuilt: %d chars; privacy hits %s' % (len(out), hits))
    if total:
        sys.exit('PRIVACY: expected 0 hits, found %d — %s' % (total, hits))

    # Cloud/platform build, if a config is set.
    if CLOUD_CONFIG_FILL:
        n = out.count(EMPTY_CONFIG)
        if n != 1:
            sys.exit('CLOUD_CONFIG marker: expected 1, found %d' % n)
        cloud = out.replace(EMPTY_CONFIG, CLOUD_CONFIG_FILL)
        os.makedirs('public', exist_ok=True)
        open(os.path.join('public', 'index.html'), 'w', encoding='utf-8').write(cloud)
        # Same privacy guarantee for the deployable build.
        clow = cloud.lower()
        chits = sum(clow.count(t) for t in ('tavern', 'rawad', 'sk-ant'))
        if chits:
            sys.exit('PRIVACY (cloud build): found %d hits' % chits)
        print('cloud build: public/index.html (%d chars)' % len(cloud))

if __name__ == '__main__':
    main()
