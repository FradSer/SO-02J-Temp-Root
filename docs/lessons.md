# What this project taught us

A cross-cutting summary. The other docs each record one operation; this one
records the rules that survived all of them. Written after two bootloops and
two full FTF reflashes.

## 1. The root is memory-state, always

Dirty COW overwrites the **page cache** of `/system/bin/run-as`. Nothing is
written to `/system` on disk, and a reboot discards the overlay. Consequences:
every reboot loses root; re-applying needs a clean page cache (reboot first,
or Dirty COW's `copyErrors` self-check silently skips the overlay).

The escalation is narrow: `uid=0` with `CapEff=00000000000000c0`
(`CAP_SETUID`/`CAP_SETGID`) and SELinux domain `u:r:shell:s0`. It cannot
`setenforce`, write `/system` or `shell_data_file`, read raw block devices, or
run `pm` (that aborts). KernelSU is not an option on `3.10.84`: GKI 2.0 needs
5.10+, and non-GKI backports stop at 4.14.

**Rule:** never plan a persistent change around this root. Persist the
*method and the artifacts*, not the privilege.

## 2. Reversibility is the single biggest safety lever

| | `pm uninstall -k --user 0` | `pm hide --user 0` |
|---|---|---|
| Visible result | Package gone for user 0 | Same |
| Undo | Impossible here (no `cmd`, no `install-existing`) | One `pm unhide` |
| Bad batch costs | Full reflash, physical button press | One reboot |

The first bootloop came from 31 irreversible uninstalls. Later, with `pm hide`,
11 packages from that very same "trigger batch" hid cleanly in small batches.
The packages were not the problem; the method was.

**Rule:** prefer a reversible operation, then make the batch small enough that
a failure is cheap. This also means old exclusion rules must be re-examined
when the method changes — see [trigger-batch-revisited.md](trigger-batch-revisited.md).

## 3. Classify by real binding signals, not by flags

Three wrong heuristics cost real time:

- `PRIVILEGED` — most `/system/priv-app` user apps carry it. It is not a
  framework dependency.
- `SVC:n` (count of entries in `dumpsys package`'s Service Resolver Table) —
  these are the package's **own declared service actions**. `osaifu.tsmproxy`
  had 3 and was perfectly removable.
- "belongs to the same family as something that once broke" — overly broad and
  not evidence.

Real signals:

| Signal | Why it matters |
|---|---|
| `sharedUser=` (`android.uid.system`, `uid.phone`, `uid.nfc`, launcher UID) | Framework assumes those components exist |
| `PERSISTENT` | Started at boot by the framework |
| declared `ContentProvider` | Other components resolve it |
| explicitly Binder-bound services (7 identified) | Framework binds them |
| active device admin | `pm hide` returns `hidden state: false` |
| resource overlay / permission-defining APK | Framework resources reference them |

**Rule:** check the target's own `dumpsys package` block. Do not infer from a
name, a flag, or a neighbour.

## 4. Health checks are necessary but never sufficient

`boot=1 ui=1 home=4 pkgs=N fatal=0` proves the system booted. It does **not**
prove anything works. Two failures were invisible to it:

- Hiding the Docomo default HOME left a `ResolverActivity` chooser on every
  boot ([launcher.md](launcher.md)).
- Hiding the preferred contact/dial handler could have broken dialling
  ([docomo-phonebook.md](docomo-phonebook.md)).

Verification ladder, in order:

1. `scripts/hide-batch.sh` — health check every 5 packages
2. `scripts/reboot-verify.sh` — **real reboot**, `sys.boot_completed=1`,
   monotonic `/proc/uptime` (not resetting to ~10s)
3. `dumpsys window | grep mFocusedApp` — no chooser, expected foreground
4. Functional check for anything that owns a preferred intent: `am start`
   the action and confirm the fallback Activity
5. Screenshot when the UI itself changed (pet overlay, wallpaper, launcher)

Also: define crashes strictly. `FATAL EXCEPTION|ANR ` is a real signal;
`"has died"` matches routine process reclamation and produces false alarms.
One `REBOOT_VERIFY_FAIL` was exactly that script inconsistency.

## 5. Reduce candidates to one before removing a preferred handler

Android picks a default automatically only when a single candidate remains.
Hiding `dhome` while `simplehome` and Xperia Home were still visible produced a
chooser. The working order was: hide the spare launcher first, reboot, then
hide the default — leaving exactly one HOME candidate.

The same reasoning applied to `socialphonebook`: AOSP `contacts` and `dialer`
were present and complete, so resolution moved to them cleanly. When the
fallback set is incomplete, do not remove the preferred handler.

## 6. Take a snapshot before anything that feels risky, and rehearse it

`scripts/snapshot.sh` records `visible.txt`, `hidden.txt`, `universe.txt`,
`settings.txt`, `meta.txt` and a generated `restore.sh`. Two snapshots exist
and both were **rehearsed**: unhide one package (246 → 247), run `restore.sh`,
then `diff` the visible set back to an exact match.

Three real bugs were found only by rehearsing:

- `IFS='=' read -r k v` truncated `max_cached_processes=4` to
  `max_cached_processes`; split on the first `=` only.
- `CDPATH` makes `cd` print an extra line, corrupting `$ROOT`; redirect it.
- `adb` consumes a `while read` loop's stdin; use fd 3.

**Rule:** an untested backup is not a backup.

## 7. Failure chronicle

| # | Trigger | Symptom | Recovery | Lesson |
|---|---|---|---|---|
| 1 | 31 `pm uninstall`s, never reboot-verified | bootloop, uptime resets ~10s | software undo blocked by SELinux; `fastboot format` did not fix it; FTF reflash | reboot-verify every batch; prefer reversible ops |
| 2 | hide `dhome` alone | HOME chooser on every boot | `pm unhide` + launch HomeActivity explicitly | reduce HOME candidates to one |
| 3 | hide `android.uid.phone` group, leaving `com.android.phone` | "Unfortunately, com.android.phone has stopped" dialog | hide `com.android.phone` itself | a shared-UID group should be handled as a unit |
| 4 | hide `com.google.android.packageinstaller` | bootloop | `pm`/`fastboot` all blocked; FTF reflash | the system installer is needed while PackageManager starts |
| 5 | `reboot-verify.sh` counted `"has died"` | false `REBOOT_VERIFY_FAIL` | strict regex | align check definitions across scripts |

The exact root cause of bootloop #1 was never proven: `fastboot format userdata`
did not fix it, which argues against per-user state alone. `recovery.md` keeps
that uncertainty explicit. Do not convert an inference into a fact.

## 8. Hard boundaries

Never hide:

- `com.google.android.packageinstaller` — bootloop #4
- `com.android.systemui`, `com.android.settings`, `com.sonyericsson.home`,
  the IME, core providers, `com.google.android.webview` (11 framework
  references), `com.sonymobile.superstamina`, `com.sonymobile.wifi`
- any `sharedUser=android.uid.system` / `uid.phone` / `uid.nfc` service
- any `PERSISTENT` service or declared provider
- resource overlays and permission-defining APKs (unless the target app is
  already hidden, making them orphans)
- active device admins (`wipe`, `remotelock`); Android 6 `dpm` has no
  `remove-active-admin`

## 9. Recovery priority, shortest first

1. `scripts/unhide-all.sh` or `adb shell sh /data/local/tmp/restore-all.sh`
   — works whenever `system_server` is up
2. `docs/snapshots/<tag>/restore.sh` — exact package state + settings
3. `fastboot format userdata` — **not reliable**; succeeded once, later
   returned `Command not allowed` on this locked bootloader
4. `scripts/restore-flash.sh` in S1 Flashmode — the only path that worked for
   both bootloops; ~3 minutes, 19 `.sin`, TA skipped, needs a physical
   Volume Down + USB press

In a bootloop the early adb window exists but PackageManager is not up, so
`pm` is unusable. Do not spend cycles retrying it. Also note that a reflash
wipes `/data`: USB debugging is reset and must be re-enabled on the device.

USB modes: `0xadde` Flashmode (green LED), `0x0dde` fastboot (blue),
`0x51e8` adb, `0x01e8` MTP without adb. After flashing, the phone usually
needs the USB cable physically unplugged to leave Flashmode.

## 10. Working habits that held up

- Batches of 1–20, health check every 5, one real reboot per batch.
- Generate `hidden-packages.txt` from the device (`pm list packages -u` minus
  `pm list packages`), never from a hand-maintained list.
- Keep identical copies in four places: repo, host, NAS, device; compare
  SHA-1 after each change.
- `unhide-all.sh` refuses a list shorter than the number of currently hidden
  packages. A stale 20-entry list once sat on the device while 63 were hidden.
- Mark historical snapshots as historical; keep active numbers current.
- Sanitize public artifacts: no serials, host paths, internal names or tokens.
- When a check fails, fix the check's definition as well as the state.

## Current state (recovered)

Bootloop #4 was recovered end to end:

1. Reflashed stock `34.1.B.0.336` in S1 Flashmode (19 `.sin`, TA skipped,
   ~190 s). The phone stayed in Flashmode until the USB cable was physically
   unplugged; `FLASHOFF_SENT` alone did not boot it.
2. Re-enabled USB debugging on the device (a reflash wipes `/data`).
3. Ran `docs/snapshots/pre-google-framework/restore.sh` — 170 packages
   re-hidden. Both `visible.txt` and `hidden.txt` matched the snapshot
   exactly, and all three recorded settings were restored.
4. `scripts/reboot-verify.sh` passed after the restore, confirming that a
   snapshot recovery also needs a real reboot check.
5. Regenerated `hidden-packages.txt` from the device (identical to the
   snapshot), rebuilt the 170-line device-side `restore-all.sh`, and re-applied
   the memory-state root.

Verified final state:

```
boot=1  ui=1  home=4  visible=241  universe=412  hidden=171
foreground HOME: com.sonyericsson.home/com.sonymobile.home.HomeActivity
running_svc=73  fatal=0  uptime 92s -> 127s (6 samples, monotonic)
uid=0(root) gid=0(root) context=u:r:shell:s0
activity_manager_constants=max_cached_processes=4
com.google.android.packageinstaller: visible (restored)
hidden-packages.txt: identical SHA-1 in repo / host / NAS / device
```

`com.google.android.packageinstaller` is deliberately visible again — it is
the package whose removal caused bootloop #4. The Google services framework
pass that preceded it is **not** restored; that work was rolled back by the
reflash and is documented as a failure, not as a desired state.
