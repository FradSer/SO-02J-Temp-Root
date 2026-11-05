#!/bin/bash
# Hide a batch of packages with health checks; record every hidden package.
# Usage: ./scripts/hide-batch.sh <list-file> [record-file]
# The record file defaults to docs/hidden-packages.txt in the repo.
#
# This is REVERSIBLE: scripts/unhide-all.sh restores everything with one command.
# Always run scripts/reboot-verify.sh after a batch. A passing health check
# before a reboot does NOT prove the device will boot (see docs/recovery.md).
set -u
ROOT="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
S=$(adb devices -l | awk '/product:SO-02J|model:SO_02J/ {print $1}' | head -1)
if [ -z "$S" ]; then echo "ERROR: SO-02J not found"; exit 1; fi
LIST=${1:?list file required}
HID=${2:-$ROOT/docs/hidden-packages.txt}
[ -f "$LIST" ] || { echo "ERROR: list not found: $LIST"; exit 1; }
touch "$HID"

health() {
  adb -s "$S" shell 'echo "boot=$(getprop sys.boot_completed) ui=$(ps 2>/dev/null | grep -c com.android.systemui) home=$(pm list packages 2>/dev/null | grep -c com.sonyericsson.home) pkgs=$(pm list packages 2>/dev/null | wc -l) fatal=$(logcat -d -t 400 2>/dev/null | grep -ciE "FATAL EXCEPTION|ANR ")"' </dev/null 2>/dev/null | tr -d '\r'
}

echo "baseline: $(health)"
n=0; ok=0; fail=0
# fd 3 keeps the list open: adb otherwise consumes the while-loop's stdin.
exec 3< "$LIST"
while read -r p <&3; do
  [ -z "$p" ] && continue
  n=$((n+1))
  out=$(adb -s "$S" shell "pm hide --user 0 $p" </dev/null 2>&1 | tr -d '\r')
  case "$out" in
    *"new hidden state: true"*) ok=$((ok+1)); grep -qx "$p" "$HID" || echo "$p" >> "$HID" ;;
    *) fail=$((fail+1)); echo "HIDE_FAIL $p : $out" ;;
  esac
  if [ $((n % 5)) -eq 0 ]; then
    h=$(health); echo "after $n: $h"
    case "$h" in
      *boot=1*ui=1*home=[1-9]*fatal=0*) ;;
      *) echo "HEALTH_BROKEN -> stop. Roll back with scripts/unhide-all.sh"; exit 2 ;;
    esac
  fi
done
exec 3<&-
echo "HIDE_BATCH_DONE n=$n ok=$ok fail=$fail"
echo "final: $(health)"
