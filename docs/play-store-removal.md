# Removing Play Store without breaking the device

The user asked for this one to be done carefully after the
`packageinstaller` bootloop. It succeeded on the first attempt. This document
records the extra checks that made it safe.

## Why this one is different from `packageinstaller`

`com.google.android.packageinstaller` is needed while `PackageManager`
starts, so hiding it breaks `system_server`. `com.android.vending` is an
ordinary privileged app:

| Property | `com.android.vending` |
|---|---|
| Path | `/system/priv-app/Phonesky/Phonesky.apk` |
| `sharedUser=` | none |
| `PERSISTENT` | no |
| `PROVIDER` in its package block | no |
| Preferred-activity entries referring to it | 0 |
| Other packages declaring `usesLibrary` from it | 0 |
| Provider | one `RecentSuggestionsProvider`, only for Play Store's own search history |

Its 59 entries in the Service Resolver Table turned out to be **14 distinct
private BIND actions it declares itself** (`InAppBillingService.BIND`,
`ILicensingService`, `IPlaySetupService.BIND`, ...), not framework bindings.
This is the classification rule from
[lessons.md](lessons.md#3-classify-by-real-binding-signals-not-by-flags)
applied before touching anything.

## Safety procedure used

1. Read-only classification of the package block, service actions, provider
   references, preferred activities, and `usesLibrary` dependents.
2. `scripts/snapshot.sh pre-playstore-hide` — records visible/hidden/universe,
   settings and a generated `restore.sh`.
3. **Rehearsed the snapshot**: unhid `com.amazon.kindle` (241 -> 242), ran
   `restore.sh`, confirmed `VISIBLE_SET_EXACT_MATCH` and that
   `max_cached_processes=4` was restored. (An earlier attempt used `pm hide`
   on a package that was already hidden, which is idempotent and does not
   actually perturb state — the rehearsal was redone with a real change.)
4. Synced and committed the snapshot **before** the change.
5. Hid exactly one package in one batch, then
   `scripts/reboot-verify.sh`.
6. Post-reboot checks beyond `boot=1`: `dumpsys window` for
   `Application Error` / chooser, foreground Activity, `FATAL EXCEPTION`,
   `ANR`, `avc: denied`, GMS/Finsky crash-loop lines, vending process count.
7. Screenshot of the home screen to confirm the icon is gone.
8. Eight stability samples over about a minute.

## Results

```
visible=241 -> 240   hidden=171 -> 172   universe=412
REBOOT_VERIFY_PASS, uptime 35s -> 45s monotonic
fatal=0  anr=0  avc=0  Application Error dialogs=0
foreground HOME: com.sonyericsson.home/com.sonymobile.home.HomeActivity
vending processes: 0
8 samples: boot=1 ui=1 pkgs=240 svc=73 fatal=0 dialog=0,
           uptime 98s -> 153s monotonic
uid=0(root) gid=0(root) context=u:r:shell:s0
hidden-packages.txt: identical SHA-1 in repo / host / NAS / device
device restore-all.sh: 172 pm unhide lines, sh -n passes
```

The Play Store icon disappeared from the home screen. GMS, GSF and WebView
were left visible; no Google framework package was touched in this pass.

## Rollback

`docs/snapshots/pre-playstore-hide/restore.sh` returns to 241 visible /
171 hidden with the recorded settings. `scripts/unhide-all.sh` restores
everything hidden.

## Rule reinforced

A package that looks "clean" is still worth a verified snapshot and a
post-reboot functional check, because `packageinstaller` looked clean too.
The difference was found in the dependency analysis, not in the flags.
