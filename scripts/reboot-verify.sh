#!/bin/bash
# Reboot and verify the device actually completes boot with hidden packages.
set -u
S=$(adb devices -l | awk '/product:SO-02J|model:SO_02J/ {print $1}' | head -1)
[ -z "$S" ] && { echo "NO_DEVICE"; exit 1; }
adb -s "$S" reboot >/dev/null 2>&1
for i in $(seq 1 90); do
  T=$(adb devices -l 2>/dev/null | awk '/product:SO-02J/ {print $1}' | head -1)
  if [ -n "$T" ]; then
    o=$(timeout 8 adb -s "$T" shell 'echo "boot=$(getprop sys.boot_completed) up=$(cat /proc/uptime | cut -d" " -f1) ui=$(ps 2>/dev/null | grep -c com.android.systemui) home=$(pm list packages 2>/dev/null | grep -c com.sonyericsson.home) pkgs=$(pm list packages 2>/dev/null | wc -l) fatal=$(logcat -d -t 400 2>/dev/null | grep -ciE "FATAL EXCEPTION|ANR ")"' 2>/dev/null | tr -d '\r' | tr '\n' ' ')
    case "$o" in *boot=1*) echo "BOOTED: $o"; break;; esac
  fi
  sleep 5
done
T=$(adb devices -l | awk '/product:SO-02J/ {print $1}' | head -1)
u1=$(adb -s "$T" shell 'cat /proc/uptime | cut -d" " -f1' 2>/dev/null | tr -d '\r')
sleep 8
u2=$(adb -s "$T" shell 'cat /proc/uptime | cut -d" " -f1' 2>/dev/null | tr -d '\r')
echo "UPTIME_MONOTONIC u1=$u1 u2=$u2"
case "$o" in *boot=1*ui=1*home=[1-9]*fatal=0*) echo "REBOOT_VERIFY_PASS";; *) echo "REBOOT_VERIFY_FAIL";; esac
