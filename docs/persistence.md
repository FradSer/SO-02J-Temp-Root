# Persistence: what survives a reboot and what does not

This is the part most easily misunderstood, so it is stated explicitly.

## Root itself does NOT persist

The root obtained here is **memory-only**:

- Dirty COW overwrites the private page-cache mapping of
  `/system/bin/run-as`. The on-disk file is never modified (dm-verity stays
  satisfied), so a reboot discards the overlay.
- `CapEff=00000000000000c0` (only `CAP_SETUID`/`CAP_SETGID`) and SELinux
  remains `Enforcing`. The escalated shell runs in `u:r:shell:s0`, not in a
  full-capability domain. It cannot write `/system`, flash a partition, or
  install a persistent `su`.
- The bootloader is locked (`Bootloader unlock allowed: No`), verified boot
  is green, and dm-verity is enforcing. There is no path to a persistent
  kernel-level root such as KernelSU or Magisk on this device. See the
  [README](../README.md#why-not-kernelsu--magisk).

**Consequence: after every reboot you must re-run the driver.**

```sh
./scripts/temp-root.sh 'id; getprop ro.build.display.id'
```

The driver deliberately reboots first. `dirtycow`'s `copyErrors()` self-check
silently reports success when the page cache already holds a previous
payload, so overlaying twice without a reboot leaves the old payload running.

## What DOES persist

| Item | Location | Survives reboot |
|---|---|---|
| `dirtycow`, `rootshell` binaries | `/data/local/tmp/` on the device | Yes (data partition) |
| `temp-root.sh`, `debloat.sh`, `monitor-load.sh` | this repository + host + NAS | Yes |
| Source files `src/*.c` | this repository | Yes |
| Firmware FTF and its hashes | host + NAS (not in this repo) | Yes |
| Per-user package uninstalls | `/data/system/users/0/package-restrictions.xml` | Yes, and NOT auto-reverted by reboot |
| Restore manifest / APK path list | `docs/restore-manifest.txt`, host, NAS | Yes |

## The scripts are the persistence mechanism

Because root cannot be made resident, the reproducible method *is* the
persistent artifact. Keep these three together:

1. `scripts/temp-root.sh` — regain uid 0 after any reboot.
2. `scripts/debloat.sh` — re-apply a vetted package list with health checks.
3. `scripts/monitor-load.sh` — verify system load after changes.

Store them on the host and on a separate machine (NAS), not only on the
phone. If the device becomes unbootable, the FTF plus `docs/flashing.md`
is the recovery path.

## Debloat is persistent but not locally reversible

On this build (Android 6.0.1) there is no `cmd` and no
`install-existing`, and `pm install -r <system apk>` does not re-register
system packages. Per-user uninstalls survive reboots. The only reliable
restore is reflashing the stock FTF in S1 Flashmode, which requires physical
access (hold Volume Down, plug USB). See [debloat.md](debloat.md).

This is why `debloat.sh` refuses to touch framework/overlay/core packages
and stops on the first health-check failure: a mistake cannot be undone from
an adb shell.
