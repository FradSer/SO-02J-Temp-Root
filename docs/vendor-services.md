# Vendor preinstalled services: how far the cleanup can safely go

Follow-up to [pet-and-overseas.md](pet-and-overseas.md). All changes use
reversible `pm hide` with a real reboot verification after each batch.

## What was removed (10 packages, two batches)

Batch 1 (9 Sony vendor services), each with no shared UID, `PERSISTENT`,
provider, or explicit framework binding:

```
com.sonymobile.entrance                     What's New / recommendation feed
com.sonymobile.fota.service                 FOTA update client
com.sonymobile.intelligent.backlight        adaptive backlight
com.sonymobile.packagecourier               package transfer helper
com.sonymobile.dlna                        DLNA media sharing
com.sonymobile.sdcardtransfer               SD card transfer
com.sonymobile.cameracommon.wearablebridge  wearable camera bridge
com.sonyericsson.autopoweroffservice        scheduled power off
com.sonyericsson.unsupportedheadsetnotifier headset warning dialog
```

Batch 2: `com.sonymobile.chargingsupport`.

Both batches passed `REBOOT_VERIFY_PASS` with `fatal=0` and the Sony Xperia
Home still in the foreground.

## Why the cleanup stops here

The remaining vendor packages are **not** ordinary apps. A classification of
the 38 remaining Sony user-level/service packages showed that almost all of
them share a privileged UID:

| Signal | Examples | Why it must stay |
|---|---|---|
| `sharedUser=android.uid.system` | `coverapp2`, `demoappchecker`, `emergencymode`, `fontselector`, `imageenhancer`, `lockscreen.otp`, `pip`, `smartcharger`, `smartcleaner`, `tvout.wifidisplay`, `coresettings`, `whitebalance`, `transmitpower` | Runs as the system UID; framework and SystemUI assume these components exist |
| `sharedUser=com.sonyericsson.home` | `advancedwidget.topcontacts`, `advancedwidget.worldclock` | Shares the launcher's UID |
| `sharedUser=android.uid.bluetooth` / `uid.shell` / `uid.phone` | `aptx.notifier`, `enterprise.installation`, Qualcomm IMS services | Radio / shell identity |
| `PERSISTENT` | `com.sonymobile.getmore` | Started at boot by the framework |
| provider | `com.sonymobile.providers.topcontacts` | Content provider consumed by other components |

Only four of the 38 had no hard binding at all, and three of those
(`externalkeyboard`, `externalkeyboardjp`, `music.googlelyricsplugin`) are in
the [bootloop trigger batch](debloat.md#round-4-the-batch-that-triggered-a-bootloop).
The fourth, `chargingsupport`, was removed in batch 2.

The `com.android.*` packages left at this point are also deliberately kept:
they are the AOSP helper components (`backupconfirm`, `calllogbackup`,
`captiveportallogin`, `printspooler`, `proxyhandler`, `sharedstoragebackup`,
`smspush`, `vpndialogs`, `wallpapercropper`, `pacprocessor`, `htmlviewer`,
`certinstaller`, `bookmarkprovider`) that were part of, or the same family as,
the batch that caused the bootloop. Hiding them again would repeat the exact
failure this project already recovered from with a full FTF reflash.

Likewise kept: all resource overlays, permission-defining APKs,
`/system/framework` packages, the 7 explicitly Binder-bound services, active
device admins, and the protected set in
[debloat.md](debloat.md#protected-set-never-remove).

## Practical rule

Counting declared service actions (`SVC:n` in `dumpsys package`'s Service
Resolver Table) is **not** a framework-binding test — those are the package's
own private actions. The real exclusion signals are:

1. `sharedUser=` (especially `android.uid.system`, `uid.phone`, `uid.nfc`,
   `uid.bluetooth`, or the launcher's UID)
2. `PERSISTENT`
3. declared `ContentProvider`
4. the seven explicitly Binder-bound services identified earlier
5. resource overlays / permission definitions

The bootloop trigger batch is **not** an automatic exclusion under `pm hide`:
[trigger-batch-revisited.md](trigger-batch-revisited.md) re-tested 11 of its
members in small batches and all hid cleanly. Treat it as a reason for extra
caution (smaller batches, one reboot check per batch), not a hard rule.

Anything with none of these can be tried in a small `pm hide` batch followed
by `scripts/reboot-verify.sh`. `pm hide` is reversible, so a bad batch costs
one reboot, not a reflash.

## Verified final state (historical snapshot of that pass)

```
visible=283   hidden=130   total=413
foreground HOME: com.sonyericsson.home/com.sonymobile.home.HomeActivity
boot=1  ui=1  home=4  running_svc=73  fatal=0
uptime 82s -> 116s (6 samples, monotonic)
uid=0(root) gid=0(root) context=u:r:shell:s0
hidden-packages.txt: identical SHA-1 in repo / host / NAS / device
device restore-all.sh: 130 pm unhide lines, sh -n passes
```
