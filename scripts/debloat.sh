#!/bin/bash
# SO-02J debloat driver - reversible-looking, but per-user uninstall is NOT
# restorable on this build. See docs/debloat.md before running.
#
# Usage: ./debloat.sh <package-list-file>
# The list must come from a vetted inventory; this script refuses to touch
# any package matching the protected core set.
set -u

S=$(adb devices -l | awk '/product:SO-02J|model:SO_02J/ {print $1}' | head -1)
if [ -z "$S" ]; then echo "ERROR: SO-02J not found"; exit 1; fi

BUILD=$(adb -s "$S" shell 'getprop ro.build.display.id' | tr -d '\r')
if [ "$BUILD" != "34.1.B.0.336" ]; then
    echo "ERROR: wrong firmware ($BUILD)"; exit 1
fi
LIST=${1:-}
if [ -z "$LIST" ] || [ ! -f "$LIST" ]; then echo "ERROR: package list required"; exit 1; fi

# Never remove: framework, overlays, SystemUI/launcher/IME/telephony,
# setup wizard, permissions, low-level services, and superstamina
# (its removal previously caused a SystemUI crash loop / black screen).
PROTECT='com.android.systemui|com.android.settings|com.android.phone|com.android.providers|com.android.server|com.android.webview|com.android.vending|com.google.android.gms|com.google.android.webview|com.qualcomm|com.qti.|com.sonyericsson.home|com.touchtype.swiftkey|com.sonymobile.superstamina|com.sonyericsson.android.servicemenu|com.sonymobile.xperiaservices|com.sonymobile.wifi|com.sonymobile.getset.priv|com.sonymobile.deviceconfigtool|\.overlay|\.permission|service|provider|daemon|sysmon'

echo "device=$S build=$BUILD"
n=0; ok=0; fail=0
while IFS= read -r p; do
    p=$(printf '%s' "$p" | tr -d '\r' | sed 's/#.*//' | xargs)
    [ -z "$p" ] && continue
    if printf '%s' "$p" | grep -qE "$PROTECT"; then
        echo "SKIP (protected): $p"; continue
    fi
    r=$(adb -s "$S" shell "pm uninstall -k --user 0 $p" </dev/null 2>&1 | tr -d '\r' | tail -1)
    n=$((n+1))
    case "$r" in
        *Success*) ok=$((ok+1));;
        *) fail=$((fail+1)); printf 'FAIL %-46s %s\n' "$p" "$r";;
    esac
    # Health check every 5 packages: stop immediately if UI/boot degrades.
    if [ $((n % 5)) -eq 0 ]; then
        h=$(adb -s "$S" shell 'echo "ui=$(ps 2>/dev/null | grep -c com.android.systemui) boot=$(getprop sys.boot_completed) home=$(pm list packages 2>/dev/null | grep -c com.sonyericsson.home)"' </dev/null 2>/dev/null | tr -d '\r')
        echo "  [after $n] $h"
        case "$h" in
            *ui=0*|*boot=0*|*home=0*) echo "HEALTH DEGRADED - STOPPING"; exit 1;;
        esac
    fi
done < "$LIST"
echo "processed=$n success=$ok failed=$fail"
adb -s "$S" shell 'echo "remaining=$(pm list packages 2>/dev/null | wc -l)"'
