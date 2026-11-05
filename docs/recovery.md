# Recovery from an over-aggressive debloat (bootloop)

This documents a real failure mode observed on this device, so it is not
repeated. Removing packages that framework binds at boot leaves the phone in
a reboot loop. Root being memory-only makes this worse: a reboot discards the
Dirty COW overlay, so there is no escalated shell available to undo the
change.

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
| `fastboot format userdata` | Succeeds (recreates the filesystem) but the device still bootloops; Sony's `dm-req-crypt` layer and dalvik-cache重建 still fail |
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
4. Unplug USB and power on. First boot after a reflash is slow (dexopt).
5. Verify: `adb shell getprop sys.boot_completed` = `1`, SystemUI present,
   `pm list packages` back to the stock count.

This restores the device to stock `34.1.B.0.336`. All per-user uninstalls
are gone. If you debloat again, stop at the protected set in
[debloat.md](debloat.md#protected-set-never-remove) and never remove packages
with Binder-bound service actions or `android.uid.system` shared UID.

## Root after recovery

The memory-only root is lost with every reboot, including this one. Re-run
`scripts/temp-root.sh` after the device boots; it reboots once to clear the
Dirty COW page cache, then re-applies the overlay. See
[persistence.md](persistence.md).
