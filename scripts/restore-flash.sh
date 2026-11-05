#!/bin/bash
# Re-flash the stock SO-02J 34.1.B.0.336 FTF to recover from a bootloop.
#
# Requirements:
#   - Phone in S1 Flashmode: power off, hold Volume Down, plug USB, wait for
#     a solid GREEN LED. USB VID:PID is 0fce:adde (fastboot's blue LED / 0fce:0dde
#     will NOT work here).
#   - A Linux host (or Linux VM with USB passthrough) with xflasher available.
#   - `work/` containing the 19 unpacked .sin files; all .ta files removed.
#
# Boot delivery and TA are deliberately skipped: the bootloader stays locked
# and DRM keys are untouched. See docs/recovery.md.
set -u
W=${W:-./work}
X=${X:-/usr/local/bin/xflasher}
LOG=${LOG:-./restore-flash.log}
: > "$LOG"
if ! lsusb 2>/dev/null | grep -qi "0fce:adde"; then
  echo "ERROR: phone not in S1 Flashmode (0fce:adde). Hold Volume Down + plug USB, wait for green LED." | tee -a "$LOG"
  exit 1
fi
cd "$W" || exit 1
echo "== step 1: S1 handshake ==" | tee -a "$LOG"
timeout 240 "$X" noloader 0 0 0FCE ADDE 0 0 >>"$LOG" 2>&1
echo "handshake rc=$?" | tee -a "$LOG"
sleep 2
echo "== step 2: reflash 19 partitions ==" | tee -a "$LOG"
for f in ssd.sin partition.sin adspso.sin amss_fsg.sin amss_fs_1.sin amss_fs_2.sin \
         apps_log.sin cache.sin diag.sin elabel.sin fotakernel.sin kernel.sin \
         modem.sin oem.sin persist.sin Qnovo.sin ramdump.sin system.sin userdata.sin; do
  echo "--- $f ---" | tee -a "$LOG"
  timeout 1200 "$X" "$f" 0 0 0FCE ADDE 0 0 >>"$LOG" 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "ERROR: failed on $f (rc=$rc). Stopping." | tee -a "$LOG"
    exit 1
  fi
done
echo "== DONE: stock firmware restored; unplug USB and power on ==" | tee -a "$LOG"
