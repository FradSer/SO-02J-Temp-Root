# Replacing the Docomo launcher with Sony Xperia Home

The stock SO-02J build ships with **`com.nttdocomo.android.dhome` as the
default HOME activity** (Docomo's Japanese launcher). It is registered as a
preferred activity with `mMatch=0x100000 mAlways=true`. Removing it is the
single most requested part of de-Japanifying this device, and it is also the
easiest way to end up with a "choose a home app" dialog or a blank screen.

## HOME candidates on this build

`dumpsys package` shows exactly three activities in the HOME category:

```
com.sonymobile.simplehome/.HomeActivity
com.sonyericsson.home/com.sonymobile.home.HomeActivity
com.nttdocomo.android.dhome/.HomeActivity    <- preferred default
```

`com.sonyericsson.androidapp.sehome` also has a `.Launcher` activity but is
**not** in the HOME resolver table. It is also one of the 31 packages from the
[bootloop batch](debloat.md#round-4-the-batch-that-triggered-a-bootloop), so
never touch it.

## What does NOT work

- **Hiding only `dhome`.** The preferred HOME entry points at a now-hidden
  component and becomes invalid. Two HOME candidates remain (`simplehome` and
  `com.sonyericsson.home`), so Android shows `android/com.android.internal.app.ResolverActivity`
  on every boot. `ui=1 home=4 pkgs=...` health checks all still pass — they do
  not detect this. Always check `dumpsys window | grep mFocusedApp`.
- **Setting a new preferred HOME from the shell.** Android 6 here has no
  `cmd` binary, and neither `pm` nor `am` offers `set-home-activity` or
  `clear-preferred`. There is no `settings` key for it either.
- **`am start -n <home>/.HomeActivity`.** This brings that launcher to the
  foreground but does not clear the invalid preferred entry; the chooser
  returns after a reboot.
- **Unhiding `dhome` alone.** It restores the package but does not dismiss an
  already-visible chooser. Launch its HomeActivity explicitly to recover.

## The order that works

With `pm hide` (reversible — see [hide-debloat.md](hide-debloat.md)), reduce
the HOME candidates to exactly **one** before removing the default:

```sh
# 1. Hide the spare launcher. Reboot and verify; dhome is still the default.
./scripts/hide-batch.sh simplehome.txt
./scripts/reboot-verify.sh

# 2. Hide the Docomo default launcher. Now com.sonyericsson.home is the only
#    HOME candidate, so Android adopts it automatically with no chooser.
./scripts/hide-batch.sh dhome.txt
./scripts/reboot-verify.sh

# 3. Verify the ACTUAL foreground activity, not just package counts.
adb shell dumpsys window | grep mFocusedApp
# expect: com.sonyericsson.home/com.sonymobile.home.HomeActivity
# NOT:    android/com.android.internal.app.ResolverActivity
```

`dumpsys window` showed `ResolverActivity` in the failed attempt and
`com.sonyericsson.home/...HomeActivity` after the two-step approach. A
screenshot after waking the screen (`input keyevent 224`, then `input keyevent
82`) confirmed the real Xperia Home desktop with icons and navigation keys.
Note that `screencap` returns an all-black image while the display is asleep —
check `dumpsys power` (`Display Power: state=ON`) before concluding the screen
is broken.

## Japanese carrier services removed alongside it

Two batches, each reboot-verified:

- 11 unbound Docomo services: `applicationmanager`, `bugreport`, `cloudset`,
  `dmenu2`, `docomoset`, `gs.utility_sha2`, `sdcardbackup`, and the
  `jp.co.nttdocomo.*` apps `anshinmode`, `bridgelauncher`, `carriermail`,
  `lcsapp`.
- 4 more clean packages: `initialization`, `socialphonebook`, and the two
  `/data/app` FeliCa wallet frontends (`mfm.main`, `mfw.a.main`).

**Deliberately kept:** every package with a `sharedUser`, `PERSISTENT`,
provider, or Binder service binding (e.g. `mascot`, `databackup`,
`schedulememo`, `phonemotion`, `osaifu.tsmproxy`); all FeliCa `mfc/mfm/mfs/mfw.a.boot`
and the 31-package bootloop batch; `remotelock` and the active device admin
`com.nttdocomo.android.wipe`; and all resource overlays.

## Rollback

`scripts/unhide-all.sh` restores all hidden packages. After a full unhide the
preferred HOME entry may again be ambiguous — launch the desired HomeActivity
explicitly if a chooser appears:

```sh
adb shell am start -a android.intent.action.MAIN \
  -c android.intent.category.HOME \
  -n com.nttdocomo.android.dhome/.HomeActivity
```

## Final state after this pass

Historical snapshot at the end of the launcher pass. Later passes
([pet-and-overseas.md](pet-and-overseas.md)) brought this to
`visible=293 hidden=120`.

```
visible=317  hidden=96  total=413
boot=1  ui=1  home=4  running_svc=73  fatal=0
foreground HOME: com.sonyericsson.home/com.sonymobile.home.HomeActivity
uptime 177s -> 213s (6 samples, monotonic)
uid=0(root) gid=0(root) context=u:r:shell:s0
```
