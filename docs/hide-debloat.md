# Reversible debloat with `pm hide` (verified on 34.1.B.0.336)

This is the recommended way to get a clean system on this device. It replaces
the `pm uninstall -k --user 0` approach in [debloat.md](debloat.md), which is
**not reversible** on this build and led to a
[bootloop](recovery.md) requiring a full FTF reflash.

## Why `pm hide` instead of `pm uninstall`

| | `pm uninstall -k --user 0` | `pm hide --user 0` |
|---|---|---|
| Effect | Package disappears for user 0 | Package disappears for user 0 (`pm list packages`) |
| APK | Stays in `/system` (read-only) | Stays in `/system`, still listed by `pm list packages -u` |
| Reversible | **No** — no `cmd`, no `install-existing`, `pm install -r` does not re-register | **Yes** — `pm unhide --user 0 <pkg>` restores it immediately |
| Recovery if something breaks | Full FTF reflash (physical button press) | One command, no reboot needed |
| Needs root | No (shell uid 2000 can do it) | No |

The memory-only root cannot help here: its SELinux domain is `u:r:shell:s0`
with only `CAP_SETUID`/`CAP_SETGID`, so it cannot write `/system` or
`setenforce`. Physically deleting system APKs is not possible. `pm hide`
reaches the same visible result without those privileges.

Verified reversibility: `pm hide` moved `com.instagram.android` from the
enabled list to `-u` only, and `pm unhide` brought it straight back with
`boot=1 ui=1` unchanged. A full 63-package rollback drill went `350 -> 413`
with `UNHIDE_DONE n=63 ok=63 fail=0`.

## Required discipline

1. **Only hide packages with no framework binding.** Exclude every package
   with `sharedUser=`, `PRIVILEGED`, `PERSISTENT`, a declared provider, or a
   service action in `dumpsys package`'s Service Resolver Table. Also keep the
   [protected set](debloat.md#protected-set-never-remove).
2. **Never repeat the round-4 batch** listed in
   [debloat.md](debloat.md#round-4-the-batch-that-triggered-a-bootloop), and
   exclude the same families (themes, skins, style/portrait resources,
   launchers, IME, provisioning, FeliCa, lockscreen, wallpaper/theme pickers).
3. **Hide in small batches** (9-20 packages), with a health check every 5.
4. **Reboot and verify after every batch.** A green health check before a
   reboot proved nothing last time. Check `sys.boot_completed=1`, SystemUI,
   the launcher, and that `/proc/uptime` keeps increasing instead of
   resetting to ~10 s.
5. **Keep the hidden list and the rollback script.** `scripts/hide-batch.sh`
   appends every hidden package to `docs/hidden-packages.txt`.

## Procedure

```sh
# 1. Snapshot the current package set (read-only review)
adb shell 'pm list packages -f' > all.txt
adb shell 'dumpsys package' > dump.txt

# 2. Hide a batch. health() runs every 5 packages and aborts on breakage.
./scripts/hide-batch.sh my-batch.txt

# 3. Reboot and verify. This is mandatory, not optional.
./scripts/reboot-verify.sh

# 4. Repeat for the next batch.

# 5. Roll back everything if needed:
./scripts/unhide-all.sh
```

`hide-batch.sh` uses fd 3 for its input list: `adb` consumes stdin otherwise,
which silently truncates the loop after one package. `unhide-all.sh` does the
same. The scripts also redirect `cd` because a `CDPATH` entry makes `cd`
print an extra line and corrupt `$ROOT`.

## Verified result on this device

Starting from the stock 413 packages, 63 were hidden in four batches of
20 / 17 / 17 / 9. Every batch passed `REBOOT_VERIFY_PASS`:

```
visible=350   hidden-total=413
boot=1  ui=1  home=4  running_svc=73  layers=7
fatal=0  avc=0  uptime 98s -> 171s (10 samples, monotonic)
```

Protected packages all confirmed present afterwards:
`com.android.systemui`, `com.android.settings`, `com.android.phone`,
`com.sonyericsson.home`, `com.touchtype.swiftkey`,
`com.sonymobile.superstamina`, `com.sonymobile.wifi`,
`com.sonymobile.xperiaservices`, `com.android.vending`,
`com.google.android.webview`.

A one-package rollback drill went `350 -> 351 -> 350`. The full 63-package
drill went `350 -> 413 -> 350`, with all four batches re-applied and each
reboot-verified again.

## What remains (350 packages) and why it stays

- 61 resource overlays and permission-defining packages
- framework packages in `/system/framework`, `android.uid.system` shared-UID
  services, Binder-bound services, privileged/persistent services
- SystemUI, Settings, telephony, dialer, contacts, IME, launcher, providers,
  WebView, Play services/Store, `com.sonymobile.wifi`, `com.sonymobile.superstamina`
- themes/skins/wallpaper pickers, launchers, IME helpers, provisioning,
  FeliCa, lockscreen and diagnostic menus — the families implicated in the
  bootloop

Removing these would break boot or SystemUI for no real gain. See
[debloat.md](debloat.md) and [recovery.md](recovery.md).
