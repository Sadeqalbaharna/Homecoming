#!/bin/sh
# Runs every tests/*.js against a build. Usage: sh tests/run.sh tavern_console_blank.html
cd "$(dirname "$0")/.." || exit 1
TARGET="${1:-tavern_console_blank.html}"
python3 -c "
import re,sys
js=re.findall(r'<script[^>]*>(.*?)</script>',open(sys.argv[1],encoding='utf-8').read(),re.S)[0]
open('/tmp/_build.js','w',encoding='utf-8').write(js)" "$TARGET"
fail=0
for t in tests/*.js; do
  case "$t" in */stub.js) continue;; esac
  cat tests/stub.js /tmp/_build.js "$t" > /tmp/_run.js
  echo "── $t ──"
  TC="$TARGET" node /tmp/_run.js || fail=1
done
exit $fail
