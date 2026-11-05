# Revisiting the "trigger batch" with reversible `pm hide`

The user pointed out that `osaifu`-prefixed apps were still present and that
the Docomo cleanup was incomplete. Checking the device confirmed
`com.nttdocomo.osaifu.tsmproxy` and 23 other Japanese-branded packages were
still visible.

## Why the earlier exclusion was too conservative

Earlier passes excluded the 31-package "bootloop trigger batch" wholesale.
That rule was established when the method was `pm uninstall -k --user 0`,
which is **not reversible** on this build. Two facts were recorded but not
fully acted on:

- The exact root cause of that bootloop was never proven. `fastboot format
  userdata` did not fix it, which argues against per-user uninstall state
  being the cause.
- `pm hide` is reversible with one `pm unhide` command and needs no reboot.

Reclassifying the 24 remaining Japanese packages by real signals (shared UID,
`PERSISTENT`, provider, overlay) showed only **3 hard-bound** packages
(`felicaremotelock` and `docomo.settings` share `android.uid.system`,
`tapandpay` shares `android.uid.nfc`) and **4 resource overlays**. The other
17 were CLEAN. Notably `osaifu.tsmproxy` declares only three private
`jp.jmnc.*` library actions — not a framework binding. The "SVC:n" counts
that had excluded it were its own declared service actions.

## What was removed (15 packages, 7 small batches)

Each batch was followed by `scripts/reboot-verify.sh`; all passed
`REBOOT_VERIFY_PASS` with `fatal=0` and Xperia Home still in the foreground.

| Batch | Packages |
|---|---|
| 1 | `osaifu.tsmproxy`, `android.lac`, `wappush` |
| 2 | `atf`, `apnsw`, `accountwipe` |
| 3 | `idmanager`, `pf.dcmippushaggregator`, `rwpushcontroller` |
| 4 | `settings.lac`, `phonemotion` (`remotelock` rejected, see below) |
| 5 | `felicanetworks.mfm`, `.mfs` |
| 6 | `felicanetworks.mfc`, `.mfw.a.boot` |

**Conclusion:** all 11 members of the former trigger batch that were still
present hid cleanly, including the four FeliCa/NFC packages. The earlier
bootloop was about the irreversible uninstall method (plus whatever made
`format userdata` fail to recover it), not about these packages being needed
at boot. This is an inference from successful reboot verification, not proof
of the original cause — see [recovery.md](recovery.md), which still marks the
root cause unproven.

The practical rule that survives: with a reversible method, small batches and
a real reboot check make it safe to test packages that were previously
excluded on suspicion alone.

## What still cannot be removed (9 packages)

| Package | Blocker |
|---|---|
| `com.nttdocomo.android.wipe` | Active device admin (`wipe-data` policy). `pm hide` returns `new hidden state: false` |
| `com.nttdocomo.android.remotelock` | Not in the active-admin list, but PackageManager's device-policy cache still rejects `pm hide`. A reboot did not clear it. Android 6 `dpm` has only `set-active-admin` / `set-device-owner` — no `remove-active-admin` — so there is no shell path to clear it |
| `com.nttdocomo.android.felicaremotelock` | `sharedUser=android.uid.system` |
| `com.nttdocomo.android.tapandpay` | `sharedUser=android.uid.nfc` |
| `com.sonyericsson.docomo.settings` | `sharedUser=android.uid.system` |
| 4 `*.res.overlay*` / `*.product.res.overlay*` | Resource overlays referenced by framework resources |

`hide-batch.sh` correctly reported `HIDE_FAIL` for `remotelock` and `wipe`
and did not add them to the rollback list. Do not try to force these: they
are remote-lock / remote-wipe security components, and the gain is small.
Trying to disable the admin needs a reboot that drops the memory-only root,
and `pm hide` itself needs no root, so the blocker is purely in the device
policy layer.

## Verified final state (historical snapshot of that pass)

```
visible=268   hidden=145   total=413
foreground HOME: com.sonyericsson.home/com.sonymobile.home.HomeActivity
boot=1  ui=1  home=4  running_svc=73  fatal=0
uptime 109s -> 144s (6 samples, monotonic)
uid=0(root) gid=0(root) context=u:r:shell:s0
hidden-packages.txt: identical SHA-1 in repo / host / NAS / device
device restore-all.sh: 145 pm unhide lines, sh -n passes
```

No `osaifu`-prefixed package remains visible.
