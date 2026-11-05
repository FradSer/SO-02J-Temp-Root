#!/bin/bash
# Rollback: unhide every package recorded in the hidden list.
# Usage: ./scripts/unhide-all.sh [list-file]
# Default list is docs/hidden-packages.txt next to this script's repo root.
set -u
DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
ROOT="$(cd "$DIR/.." >/dev/null 2>&1 && pwd)"
# Resolve the list next to the script first, then the repo docs/ layout.
if [ -n "${1:-}" ]; then LIST=$1
else
  LIST=""
  for c in "$DIR/hidden-packages.txt" "$DIR/hidden.txt" "$ROOT/docs/hidden-packages.txt"; do
    [ -f "$c" ] && { LIST=$c; break; }
  done
  [ -z "$LIST" ] && { echo "ERROR: no hidden-packages.txt next to the script or in docs/"; exit 1; }
fi
# Guard against a stale partial list: it must contain every currently hidden
# package, otherwise a rollback would silently leave some hidden.
S=$(adb devices -l | awk '/product:SO-02J|model:SO_02J/ {print $1}' | head -1)
if [ -z "$S" ]; then echo "ERROR: SO-02J not found"; exit 1; fi
if [ ! -f "$LIST" ]; then echo "ERROR: list not found: $LIST"; exit 1; fi
ACTUAL=$(adb -s "$S" shell 'pm list packages -u' 2>/dev/null | tr -d '\r' | sed 's/^package://' | sort)
VISIBLE=$(adb -s "$S" shell 'pm list packages' 2>/dev/null | tr -d '\r' | sed 's/^package://' | sort)
HIDCOUNT=$(printf '%s\n' "$ACTUAL" | comm -23 <(printf '%s\n' "$ACTUAL") <(printf '%s\n' "$VISIBLE") | grep -c .)
LISTCOUNT=$(grep -c . "$LIST")
if [ "$LISTCOUNT" -lt "$HIDCOUNT" ]; then
  echo "ERROR: $LIST has $LISTCOUNT packages but $HIDCOUNT are hidden; refusing an incomplete rollback."
  echo "Use the full docs/hidden-packages.txt instead."
  exit 1
fi
echo "rollback list: $LIST ($LISTCOUNT entries; device hidden: $HIDCOUNT)"

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
