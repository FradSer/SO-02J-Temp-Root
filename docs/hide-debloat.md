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
`boot=1 ui=1` unchanged. A full rollback drill (at that point 63 packages)
went `350 -> 413` with `UNHIDE_DONE n=63 ok=63 fail=0`; the same four batches
were then re-applied and each reboot-verified again. The current list has 79
packages, generated from the device after two further batches.

## Required discipline

1. **Only hide packages with no framework binding.** Exclude every package
   with `sharedUser=`, `PRIVILEGED`, `PERSISTENT`, a declared provider, or a
   service action in `dumpsys package`'s Service Resolver Table. Also keep the
   [protected set](debloat.md#protected-set-never-remove).
2. **Do not remove framework-bound packages.** Exclude shared UIDs,
   `PERSISTENT`, declared providers, resource overlays, permission
   definitions, and active device admins. The old "never repeat the round-4
   batch" rule applied to irreversible `pm uninstall`; with reversible
   `pm hide` and per-batch reboot verification, most of that batch proved
   safe — see [trigger-batch-revisited.md](trigger-batch-revisited.md).
   Still avoid themes, skins, style/portrait resources, launchers, IME, and
   provisioning families, which were never re-tested.
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

Starting from the stock 413 packages, **96 are hidden** and 317 visible.
Every batch passed `REBOOT_VERIFY_PASS`. The batches were:

1. Four batches (63 packages) covering user-level apps from the previously
   verified removal set: social/Japanese apps, Google entertainment, Sony
   media utilities, Docomo value-add apps.
2. Three more batches (16 packages) after a fresh `dumpsys package`
   classification excluded every package with a shared UID, `PERSISTENT`,
   provider, or Binder service binding: camera/media suite, AOSP utilities,
   Docomo store, and two `/data/app` leftovers.
3. The Japanese launcher/service pass documented in
   [launcher.md](launcher.md): 15 Docomo services and the two-step default
   launcher replacement (`dhome` -> `com.sonyericsson.home`).

A failed attempt to hide only `dhome` produced a HOME chooser; that is why
`launcher.md` records the required order. Check the foreground activity, not
just package counts, after any launcher change.

```
visible=240   hidden-total=412   hidden=172
foreground HOME: com.sonyericsson.home/com.sonymobile.home.HomeActivity
boot=1  ui=1  home=4  running_svc=73
fatal=0  uptime 98s -> 153s (8 samples, monotonic)
```

`docs/hidden-packages.txt` is generated from the device itself
(`pm list packages -u` minus `pm list packages`) so the rollback list can
never drift from reality. The same file is staged on the device, the host and
the NAS, with identical SHA-1.

Protected packages all confirmed present afterwards:
`com.android.systemui`, `com.android.settings`, `com.android.phone`,
`com.sonyericsson.home`, `com.touchtype.swiftkey`,
`com.sonymobile.superstamina`, `com.sonymobile.wifi`,
`com.sonymobile.xperiaservices`, `com.android.vending`,
`com.google.android.webview`.

A one-package rollback drill went `350 -> 351 -> 350`. The full 63-package
drill went `350 -> 413 -> 350`, with all four batches re-applied and each
reboot-verified again. `unhide-all.sh` now refuses a list shorter than the
number of currently hidden packages.

## What remains (263 packages) and why it stays

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
