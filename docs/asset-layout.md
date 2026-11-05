# Asset layout and recovery quick reference

One authoritative copy of each artifact, so cleanup does not accidentally
delete the only working recovery path.

## Where things live

| Asset | Authoritative location | Also copied to |
|---|---|---|
| Method, scripts, package lists | Public GitHub repo `FradSer/SO-02J-Temp-Root` | local clone, host working dir, NAS share |
| Local git clone | a persistent local clone (outside `/tmp`) | — |
| Stock FTF (2.4 GB) | local FTF copy | NAS `firmware/` |
| Unpacked `.sin` partitions (19) | OrbStack guest `so02j:/opt/so02j/work` | NAS `work/` |
| Built `xflasher` (Linux usbfs) | OrbStack guest `/usr/local/bin/xflasher` | NAS `src/xflasher` (amd64 build) |
| `xflasher` source | host `so02j-src/` | NAS `src/` |
| APK backups (175 MB) | host `backup-apks/` | NAS `backup-apks/` |
| Hidden package list (150) | repo `docs/hidden-packages.txt` | host, NAS, device `/data/local/tmp/hidden.txt` |

The local clone originally lived in `/tmp`; it was moved to a persistent
location so a reboot cannot wipe the only local git working copy.

## Recovery paths, shortest first

| Problem | Fix |
|---|---|
| Need to undo the debloat | `scripts/unhide-all.sh` (host), or `adb shell sh /data/local/tmp/restore-all.sh` (device, self-contained, no adb needed) |
| Lost root after reboot | `scripts/temp-root.sh`. If injecting by hand, reboot first so the Dirty COW page cache is clean |
| Device bootloops and cannot be recovered in software | `scripts/restore-flash.sh` in S1 Flashmode (see [recovery.md](recovery.md)) |
| Phone stuck in Flashmode after reflash | `scripts/flashoff.c` sends `CMD_FLASHMODE_OFF` — no button press needed |
| USB debugging disappeared after reflash | Expected: `userdata.sin` wipes `/data`. Re-enable Developer options on the device |

`unhide-all.sh` refuses to run if its list is shorter than the number of
currently hidden packages. This guards against an outdated partial list: an
earlier cleanup pass found a stale 20-entry list on the device while 63
packages were hidden. Always use the full `docs/hidden-packages.txt`.

## Cleanup decisions (kept deliberately)

- **Archived, not deleted:** failed BackupTA/Flashtool experiments
  (`backupTA.sh`, `dumpta`, `exploitta`, `run-as`, `recover.c`) and the
  superseded `pm uninstall` restore manifests. They live in `archive/`
  subdirectories on the host and NAS, and are documented in
  [temp-root.md](temp-root.md) and [debloat.md](debloat.md).
- **Deleted:** one-off `/tmp` scratch scripts, screenshots, classifier
  output and intermediate package lists; scratch copies of `xflasher`,
  `newflasher`, `kugo_bins`; the unused Flashtool dmg (66 MB) and its
  mounted volume. The working path is FTF + `xflasher`, not Flashtool.
- **Not touched:** files belonging to other tasks in `/tmp` (`odk-*`,
  `cleanup_ast*`, `match_*`, `cl-real-root`, etc.).
- **Kept running:** the OrbStack `so02j` Linux guest. It holds the only
  tested `xflasher` binary and the 19 unpacked partitions needed for a
  reflash. Stopping it would remove the fastest hardware-recovery path.

## Verification after cleanup

```
boot=1 ui=1 home=4 visible=263 total=413 svc=73 fatal=0
uid=0(root) gid=0(root) context=u:r:shell:s0
hidden-packages.txt: identical SHA-1 in repo / host / NAS / device
unhide-all.sh: refuses a stale short list; 63-package rollback drill
  (350 -> 413 -> 350) passed earlier, with all batches re-applied and
  reboot-verified
```
