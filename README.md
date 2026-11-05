# SO-02J Temporary Root

A reproducible, **memory-only** root method for the Sony Xperia X Compact
NTT Docomo variant (`SO-02J`, codename `kugo`, platform `Loire`/MSM8956),
stock firmware `34.1.B.0.336` (Android 6.0.1, kernel 3.10.84, SPL 2016-07-01).

This repository documents the chain end to end: downgrade from Android 8.0,
S1 Flashmode flashing over USB passthrough, and a Dirty COW based temporary
root payload. Nothing is written to `/system` on disk; a reboot restores the
stock `run-as` binary.

> For research and repair of a device you own. The bootloader stays locked and
> the Trim Area (TA / DRM keys) is never modified. Do not use this on devices
> you are not authorised to test.

## Why not KernelSU / Magisk

| Blocker | Evidence |
|---|---|
| Kernel version | `3.10.84` — official KernelSU targets GKI 2.0 (5.10+); non-GKI backports stop at 4.14 and were dropped in KernelSU v1.0 |
| No kernel image can be flashed | `ro.boot.veritymode=enforcing`, `sys.oem_unlock_allowed=0`, service menu reports `Bootloader unlock allowed: No`. A root shell cannot write the boot partition (SELinux denial) |
| No unlocked bootloader / custom recovery | `recovery` and `FOTAKernel` partitions are inaccessible; the device has no TWRP build in this chain |

Magisk-style solutions need a patched `boot.img` and an unlocked bootloader.
Neither is attainable here. The only working root on this firmware is the
temporary, in-memory one below.

## The chain

1. **Firmware** — stock FTF `SO-02J_34.1.B.0.336_1305-8403_R13B.ftf`
   (Android 6.0.1). Verify SHA/MD5 before use; see [docs/firmware.md](docs/firmware.md).
2. **Flash** — downgrade via S1 Flashmode (`0fce:adde`) with `xflasher`.
   Boot delivery (bootloader bundles) and all `.ta` files are deliberately
   skipped, so the bootloader stays locked and TA/DRM keys survive. See
   [docs/flashing.md](docs/flashing.md).
3. **Temporary root** — Dirty COW (CVE-2016-5195) overwrites the page cache of
   `/system/bin/run-as`, whose `runas_exec` SELinux label grants
   `CAP_SETUID`/`CAP_SETGID`. The payload then switches SELinux context and
   execs a shell. See [docs/temp-root.md](docs/temp-root.md).

### Result

```
uid=0 euid=0 ctx_index=5 ctx=u:r:shell:s0
uid=0(root) gid=0(root) groups=0(root) context=u:r:shell:s0
34.1.B.0.336
6.0.1
```

## Limitations (read this)

- **Reboot loses root.** `scripts/temp-root.sh` reboots first to clear any prior
  Dirty COW overlay, then re-applies it. `dirtycow`'s `copyErrors` self-check
  silently skips a second overlay on the same dirty page cache. See
  [docs/persistence.md](docs/persistence.md) — the scripts are the persistence
  mechanism, not the root itself.
- **Restricted capability set.** `CapEff=00000000000000c0` (only
  `CAP_SETUID`/`CAP_SETGID`), and SELinux stays `Enforcing`. Root can run
  commands but cannot write `shell_data_file`, read raw block devices, or call
  `setenforce`. This is not a full root for installing modules.
- **Firmware-specific.** The payload targets `34.1.B.0.336` only. Verify the
  build before running.
- **SELinux `setenforce` is denied** to the `runas` domain; the payload instead
  switches context through `/proc/self/attr/current` to the least-restrictive
  allowed domain before exec.

## Files

| Path | What it is |
|---|---|
| `src/rootshell.c` | Freestanding aarch64 payload: `capset` → `setresuid(0)` → `setcon` → `execve(sh)`. No libc, no `.bss` |
| `src/rootproof.c` | Minimal payload that only prints uid/gid — used to prove escalation |
| `scripts/temp-root.sh` | One-shot driver: firmware guard, reboot, push, Dirty COW overlay, run commands |
| `docs/firmware.md` | Firmware identity, sources, integrity verification |
| `docs/flashing.md` | S1 Flashmode downgrade procedure and pitfalls |
| `docs/temp-root.md` | Payload design, syscall table, SELinux details, build command |
| `docs/persistence.md` | What survives a reboot and what does not; why root must be re-applied |
| `docs/debloat.md` | Protected package set, device-admin blocker, post-debloat verification |
| `docs/restore-manifest.txt` | Per-user uninstalled packages and their APK paths |
| `docs/all-system-apks.txt` | Full preinstalled package/path inventory (text only) |
| `scripts/debloat.sh` | Vetted package-list driver with a health check every 5 removals |
| `scripts/monitor-load.sh` | Two load/stability monitors, 12 samples each |

Third-party binaries (`dirtycow`, `xflasher`, FTF archives) are **not**
redistributed here. Obtain them from their upstream projects.

## Build

On any aarch64 Linux host (or an aarch64 Linux VM with USB passthrough):

```sh
gcc -O2 -Wall -ffreestanding -fno-builtin \
    -no-pie -nostdlib -static -Wl,-z,max-page-size=4096 \
    -o rootshell src/rootshell.c
```

`-nostdlib -static` and the absence of `.bss` matter: Android 6 mishandles a
zero-`FileSiz` NOBITS `LOAD` segment, and a dynamic payload would need bionic.

## Disclaimer

This is a record of work on one device. Flashing firmware can brick a phone;
downgrading across major Android versions can bootloop. Keep backups, verify
hashes, and never flash `.ta` files from a different device variant.
