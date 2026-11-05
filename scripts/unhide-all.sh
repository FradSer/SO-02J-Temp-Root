#!/bin/bash
# Rollback: unhide every package recorded in the hidden list.
# Usage: ./scripts/unhide-all.sh [list-file]
# Default list is docs/hidden-packages.txt next to this script's repo root.
set -u
ROOT="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
LIST=${1:-$ROOT/docs/hidden-packages.txt}
S=$(adb devices -l | awk '/product:SO-02J|model:SO_02J/ {print $1}' | head -1)
if [ -z "$S" ]; then echo "ERROR: SO-02J not found"; exit 1; fi
if [ ! -f "$LIST" ]; then echo "ERROR: list not found: $LIST"; exit 1; fi

n=0; ok=0; fail=0
# fd 3 keeps the list open: adb otherwise consumes the while-loop's stdin.
exec 3< "$LIST"
while read -r p <&3; do
  [ -z "$p" ] && continue
  n=$((n+1))
  out=$(adb -s "$S" shell "pm unhide --user 0 $p" </dev/null 2>&1 | tr -d '\r')
  case "$out" in
    *"new hidden state: false"*) ok=$((ok+1)) ;;
    *) fail=$((fail+1)); echo "FAIL $p: $out" ;;
  esac
done
exec 3<&-
echo "UNHIDE_DONE n=$n ok=$ok fail=$fail"
