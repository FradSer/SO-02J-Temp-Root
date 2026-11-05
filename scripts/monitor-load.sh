#!/bin/bash
# Two load-monitor tasks for SO-02J after debloat.
# Task A: device resource load. Task B: system stability.
# Each takes 12 samples at 5s intervals. Run them concurrently:
#   ./monitor-load.sh load & ./monitor-load.sh health & wait
set -u
S=$(adb devices -l | awk '/product:SO-02J|model:SO_02J/ {print $1}' | head -1)
if [ -z "$S" ]; then echo "ERROR: SO-02J not found"; exit 1; fi

MODE=${1:-load}
N=${2:-12}

case "$MODE" in
  load)
    for i in $(seq 1 "$N"); do
      echo "=== LOAD SAMPLE $i ==="
      adb -s "$S" shell '
        echo "loadavg=$(cat /proc/loadavg)"
        grep -E "^(MemTotal|MemFree|MemAvailable):" /proc/meminfo
        echo "procs=$(ls /proc | grep -c "^[0-9]")"
        echo "cpu=$(head -1 /proc/stat)"
        echo "battery=$(dumpsys battery | grep -i level: | head -1)"
        echo "temp=$(dumpsys battery | grep -i temperature: | head -1)"
        echo "systemui=$(ps 2>/dev/null | grep -c com.android.systemui)"
      ' 2>&1
      sleep 5
    done
    echo "DEVICE_LOAD_MONITOR_DONE samples=$N"
    ;;
  health)
    for i in $(seq 1 "$N"); do
      echo "=== HEALTH SAMPLE $i ==="
      adb -s "$S" shell '
        echo "boot=$(getprop sys.boot_completed)"
        echo "layers=$(dumpsys SurfaceFlinger 2>/dev/null | grep -io "Visible layers (count = [0-9]*)" | head -1)"
        echo "systemui=$(ps 2>/dev/null | grep -c com.android.systemui)"
        echo "running_svc=$(getprop | grep -c "^\[init.svc.*running\]")"
        echo "installed=$(pm list packages 2>/dev/null | wc -l)"
        echo "avc_denials=$(logcat -d -t 200 2>/dev/null | grep -ci "avc: denied")"
        echo "crash_lines=$(logcat -d -t 200 2>/dev/null | grep -ciE "ANR|FATAL EXCEPTION|died|crash")"
      ' 2>&1
      sleep 5
    done
    echo "SYSTEM_HEALTH_MONITOR_DONE samples=$N"
    ;;
  *) echo "usage: $0 {load|health} [samples]"; exit 1;;
esac
