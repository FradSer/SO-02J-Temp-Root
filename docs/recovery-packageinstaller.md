# Recovery from the `packageinstaller` bootloop

## What happened

Hiding `com.google.android.packageinstaller` (the last package in the
Google-framework cleanup) put the device into a reboot loop:

```
uptime resets 12s -> 18s -> 24s -> offline -> 12s ...
sys.boot_completed never becomes 1; systemui=0; pm list packages returns 0
```

This is the same shape as the earlier over-debloat bootloop
([recovery.md](recovery.md)), but caused by a **single** package. The system
installer is needed while `PackageManager` starts, so hiding it prevents
`system_server` from completing boot.

## Why every software rollback failed

| Attempt | Result |
|---|---|
| `pm unhide --user 0 com.google.android.packageinstaller` in the early-boot window | `Could not access the Package Manager. Is the system running?` |
| Device-side `sh /data/local/tmp/restore-all.sh` | Same — `pm` unavailable before system_server is up |
| `fastboot format userdata` | `Writing 'userdata' FAILED (remote: 'Command not allowed')` |
| `fastboot erase userdata` / `erase cache` | `Command not allowed` |
| `fastboot format:ext4 userdata` | `Command not allowed` |
| `fastboot oem reboot-flashmode` / `oem reboot-flash` / `oem flashmode` | `unknown command` |
| `adb reboot recovery` | Returns to the same loop |

Locked bootloader (`secure: yes`) blocks all partition writes from fastboot.
The earlier successful `fastboot format userdata` was a different fastboot
build/session; it cannot be relied on.

## The working recovery: reflash the stock FTF in S1 Flashmode

**Requires one physical action.** Power the phone off (long-press power),
then hold **Volume Down** and plug in USB until the LED is solid **green**.
USB VID:PID is `0fce:adde`. Blue-LED fastboot (`0fce:0dde`) cannot flash FTF.

Then, from the OrbStack Linux guest with USB passthrough:

```sh
orbctl usb attach <sony-id>
orb -m so02j -u root bash /opt/so02j/restore.sh
```

`restore.sh` reflashes the 19 `.sin` partitions and skips boot delivery and
all `.ta` files, so the bootloader stays locked and TA/DRM keys are untouched.
It took about 3 minutes on the previous recovery. After it finishes, use
`scripts/flashoff.c` (send S1 `CMD_FLASHMODE_OFF`) to boot without a button
press, or simply unplug USB and power on.

## After the reflash

Reflashing `userdata.sin` wipes `/data`, so **USB debugging is reset**. Re-enable
it on the device (Settings > About phone > tap Build number 7 times >
Developer options > USB debugging), then accept the RSA prompt.

Then restore the exact package state from the verified snapshot:

```sh
./scripts/snapshot.sh --help    # for reference
cd docs/snapshots/pre-google-framework && ./restore.sh
```

`pre-google-framework` is the state **before** the Google-framework pass:
`visible=243 hidden=170 universe=413`, with `activity_manager_constants=
max_cached_processes=4`. Its `restore.sh` was verified by perturbing the
state (unhide one package -> 244) and confirming it returned to the exact
visible set (`VISIBLE_SET_EXACT_MATCH`) and the original settings.

If you prefer an earlier state, `pre-music-album-clock`
(`visible=246 hidden=167`) is also available.

## Do not repeat

`com.google.android.packageinstaller` must stay visible. The Google services
framework packages that hid cleanly (in small, individually reboot-verified
batches) were:

```
com.google.android.onetimeinitializer
com.google.android.configupdater
com.android.vending
com.google.android.gsf.login
com.google.android.backuptransport
com.google.android.gsf
com.google.android.gms
com.google.android.setupwizard
```

`com.google.android.webview` was deliberately kept (11 references in the
framework dump); it is the system WebView provider.

## Verified toolchain state at the time of this failure

```
OrbStack guest so02j: xflasher 75072 bytes, 19 .sin, 7 .ta excluded,
                      restore.sh, flashoff
FTF md5: ac99dc8430040c3e8517eb2be009dcd1 (host and NAS identical)
Snapshots: pre-google-framework, pre-music-album-clock
           (repo, host ~/Downloads/so02j-root, NAS)
```
