#!/bin/bash
# Take a precise, restorable snapshot of the SO-02J package state.
# Usage: ./scripts/snapshot.sh [tag]
# Writes docs/snapshots/<tag>/ with: visible.txt, hidden.txt, universe.txt,
# settings.txt, meta.txt, and a ready-to-run restore.sh.
set -u
ROOT="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
S=$(adb devices -l | awk '/product:SO-02J|model:SO_02J/ {print $1}' | head -1)
if [ -z "$S" ]; then echo "ERROR: SO-02J not found"; exit 1; fi
TAG=${1:-$(date +%Y%m%d-%H%M%S)}
DIR="$ROOT/docs/snapshots/$TAG"
mkdir -p "$DIR"

adb -s "$S" shell 'pm list packages' 2>/dev/null | tr -d '\r' | sed 's/^package://' | sort > "$DIR/visible.txt"
adb -s "$S" shell 'pm list packages -u' 2>/dev/null | tr -d '\r' | sed 's/^package://' | sort > "$DIR/universe.txt"
comm -23 "$DIR/universe.txt" "$DIR/visible.txt" > "$DIR/hidden.txt"

{
  echo "# snapshot $TAG"
  echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "device=SO-02J (serial omitted)"
  adb -s "$S" shell 'echo "build=$(getprop ro.build.display.id) android=$(getprop ro.build.version.release) boot=$(getprop sys.boot_completed)"' 2>/dev/null | tr -d '\r'
  echo "visible=$(wc -l < "$DIR/visible.txt")"
  echo "hidden=$(wc -l < "$DIR/hidden.txt")"
  echo "universe=$(wc -l < "$DIR/universe.txt")"
  echo "foreground_home=$(adb -s "$S" shell 'dumpsys window 2>/dev/null | grep -i mFocusedApp | head -1' | tr -d '\r')"
} > "$DIR/meta.txt"

# Persisted system settings that affect background processes / behave differently
# from package state. Record them explicitly so a restore can reproduce them.
{
  echo "activity_manager_constants=$(adb -s "$S" shell 'settings get global activity_manager_constants' 2>/dev/null | tr -d '\r')"
  echo "app_idle_constants=$(adb -s "$S" shell 'settings get global app_idle_constants' 2>/dev/null | tr -d '\r')"
  echo "development_settings_enabled=$(adb -s "$S" shell 'settings get global development_settings_enabled' 2>/dev/null | tr -d '\r')"
} > "$DIR/settings.txt"

cat > "$DIR/restore.sh" <<'EOS'
#!/bin/bash
# Restore the device to this snapshot's exact package state.
# Usage: adb shell-independent; run from a computer: ./restore.sh
set -u
HERE="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
S=$(adb devices -l | awk '/product:SO-02J|model:SO_02J/ {print $1}' | head -1)
if [ -z "$S" ]; then echo "ERROR: SO-02J not found"; exit 1; fi
echo "Restoring snapshot from $HERE"
# 1. Unhide everything currently hidden.
CUR_UNI=$(adb -s "$S" shell 'pm list packages -u' 2>/dev/null | tr -d '\r' | sed 's/^package://' | sort)
CUR_VIS=$(adb -s "$S" shell 'pm list packages' 2>/dev/null | tr -d '\r' | sed 's/^package://' | sort)
CUR_HID=$(comm -23 <(printf '%s\n' "$CUR_UNI") <(printf '%s\n' "$CUR_VIS") | grep -v '^$' || true)
n=0
exec 3< <(printf '%s\n' "$CUR_HID")
while read -r p <&3; do
  [ -z "$p" ] && continue
  adb -s "$S" shell "pm unhide --user 0 $p" </dev/null >/dev/null 2>&1
  n=$((n+1))
done
exec 3<&-
echo "unhid $n packages"
# 2. Re-hide exactly the packages that were hidden in the snapshot.
m=0
exec 3< "$HERE/hidden.txt"
while read -r p <&3; do
  [ -z "$p" ] && continue
  adb -s "$S" shell "pm hide --user 0 $p" </dev/null >/dev/null 2>&1
  m=$((m+1))
done
exec 3<&-
echo "re-hid $m packages"
# 3. Restore recorded settings.
while IFS= read -r line; do
  [ -z "$line" ] && continue
  k=${line%%=*}; v=${line#*=}          # split on the FIRST '=' only
  [ "$k" = "$line" ] && continue
  case "$v" in null|''|*' '*) continue;; esac
  case "$k" in
    activity_manager_constants|app_idle_constants|development_settings_enabled)
      adb -s "$S" shell "settings put global $k '$v'" </dev/null >/dev/null 2>&1 ;;
  esac
done < "$HERE/settings.txt"
V=$(adb -s "$S" shell 'pm list packages | wc -l' | tr -d '\r')
H=$(adb -s "$S" shell 'pm list packages -u | wc -l' | tr -d '\r')
echo "RESTORE_DONE visible=$V universe=$H (expected visible=$(wc -l < "$HERE/visible.txt") universe=$(wc -l < "$HERE/universe.txt"))"
EOS
chmod +x "$DIR/restore.sh"

echo "SNAPSHOT_WRITTEN $DIR"
echo "  visible=$(wc -l < "$DIR/visible.txt") hidden=$(wc -l < "$DIR/hidden.txt") universe=$(wc -l < "$DIR/universe.txt")"
cat "$DIR/settings.txt"
