# Recovery from an over-aggressive debloat (bootloop)

This documents a real failure mode observed on this device, so it is not
repeated. The bootloop started immediately after the fourth debloat round,
which removed 31 packages (some AOSP helpers, FeliCa and Qualcomm items).

**The exact root cause was not proven.** The inference is that one or more of
those packages is needed by framework at boot, but two observations sit
against it: `fastboot format userdata` succeeded and did not fix the loop, and
PackageManager was observed rescanning all system APKs during an early-boot
window. The `dm-req-crypt` layer on `/data` may also have been left
inconsistent by formatting. Do not treat the package list as a confirmed
cause; treat it as the trigger to avoid.

Root being memory-only makes recovery harder: a reboot discards the Dirty COW
overlay, so there is no escalated shell available to undo the change.

## Symptoms

```
uptime repeatedly resets to ~10s, then ~17s, then ~24s, then the device drops
off USB and starts again.
sys.boot_completed is empty; com.android.systemui count is 0.
logcat stops at "Zygote: Preloading classes..." or
"ServiceManager: Waiting for service sensorservice...".
```

An `adb shell` window exists only briefly during each early-boot attempt, and
PackageManager is not yet available (`Could not access the Package Manager.
Is the system running?`).

## Why software-side undo fails

| Attempt | Result |
|---|---|
| `pm install -r <system apk>` | PackageManager not running; previously also failed to re-register system packages |
| `dpm remove-active-admin` | Only affects the admin list, not the bootloop |
| Dirty COW back to uid 0 in the early-boot window | Works (`uid=0(root)`), but SELinux still denies `setenforce` and `unlink` on `system_data_file` (`-13 EACCES`) |
| `fastboot erase userdata` / `fastboot erase cache` | `Command not allowed` (locked bootloader) |
| `fastboot format userdata` | Succeeds (recreates the filesystem) but the device still bootloops; Sony's `dm-req-crypt` layer and dalvik-cache rebuild still fail |
| `fastboot flashing unlock`, `oem reboot-flashmode`, `oem poweroff` | `unknown command` on this locked bootloader |
| `adb reboot recovery` | Device returns to the same early-boot loop |

Nothing here can be completed by an agent without physical button access.
Do not keep retrying: each attempt costs another reboot cycle.

## The recovery that works: reflash the stock FTF

1. **Power the phone off** (it will be in fastboot / blue LED or looping).
   Hold the power button until it vibrates and powers down.
2. **Enter S1 Flashmode**: hold **Volume Down**, plug USB, wait for a solid
   **green** LED. USB VID:PID is `0fce:adde`. The blue-LED fastboot mode
   (`0fce:0dde`) cannot be used for FTF flashing.
3. Run `scripts/restore-flash.sh` on a Linux host with USB passthrough. It
   reflashes the 19 `.sin` partitions from the stock FTF. Boot delivery and
   `.ta` files are skipped: the bootloader stays locked and TA/DRM keys are
   untouched. Reflashing takes roughly 3 minutes.
4. Exit Flashmode: either unplug USB and power on with the power button, or
   run `scripts/flashoff.c` (no button press needed). First boot after a
   reflash is slow (dexopt).
5. Verify: `adb shell getprop sys.boot_completed` = `1`, SystemUI present,
   `pm list packages` back to the stock count. ADB will be unavailable until
   USB debugging is re-enabled (see below).

This restores the device to stock `34.1.B.0.336`. All per-user uninstalls
are gone. Verified post-reflash baseline on this device:

```
boot=1  ui=1  home=4  installed=413
layers=Visible layers (count = 9)  running_svc=72
avc=0  crash=0  build=34.1.B.0.336  android=6.0.1
```

If you debloat again, stop at the protected set in
[debloat.md](debloat.md#protected-set-never-remove) and never remove packages
with Binder-bound service actions or `android.uid.system` shared UID.
Debloat in small batches with a health check after each batch, and verify
after an actual reboot before continuing.

## After the reflash: USB debugging is reset

Reflashing `userdata.sin` wipes `/data`, so the USB debugging setting and
ADB authorisation are reset. The phone enumerates as `0fce:01e8` (MTP only,
no ADB interface). No computer-side command can turn USB debugging back on
after a factory reset - it must be done on the device:

1. Settings > About phone > tap **Build number** 7 times.
2. Settings > Developer options > enable **USB debugging**.
3. Reconnect USB and accept the RSA prompt.

Use `scripts/flashoff.c` to kick the device out of Flashmode without a button
press after flashing. It sends the S1 `CMD_FLASHMODE_OFF` command (opcode
`0x04`, `FLAG3`, zero length, xor checksum +7) over usbfs:

```sh
gcc -O2 -Wall -o flashoff scripts/flashoff.c   # Linux host with USB passthrough
./flashoff
```

Note that USB debugging being reset is expected and is not a fault: the
firmware itself is intact. Confirm a clean boot with:

```sh
adb shell getprop sys.boot_completed      # 1
adb shell 'ps | grep -c com.android.systemui'   # >=1
adb shell 'pm list packages | wc -l'      # back to the stock count
```

## Root after recovery

The memory-only root is lost with every reboot, including this one. Once USB
debugging is back on, the safest path after a reflash is **no reboot at all**:
the page cache is already clean, so push the two binaries and inject once.

```sh
adb push dirtycow  /data/local/tmp/dirtycow
adb push rootshell /data/local/tmp/rootshell
adb shell 'chmod 755 /data/local/tmp/dirtycow /data/local/tmp/rootshell'
adb shell 'cd /data/local/tmp && ./dirtycow /system/bin/run-as ./rootshell'
# feed commands via a pushed file and stdin; always append `exit`
adb shell '/system/bin/run-as < /data/local/tmp/rootcmd.sh'
```

Verified result: `uid=0(root) gid=0(root) context=u:r:shell:s0`, `boot=1`,
`installed=413` unchanged. Four `avc: denied { dyntransition }` lines from
`run-as` are expected: the payload probes `kernel`, `init`, `zygote` and
`system_server` contexts before landing on `u:r:shell:s0`. No service deaths.

`scripts/temp-root.sh` remains the general driver; it reboots first to
guarantee a clean page cache, which is unnecessary right after a reflash.
See [persistence.md](persistence.md).
