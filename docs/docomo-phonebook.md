# Removing the Docomo Phonebook

The user asked for the Docomo phonebook to be removed.
`com.nttdocomo.android.socialphonebook` had already been hidden in an earlier
pass, but the Sony/Docomo `Phonebook.apk` and its overlays were still visible.

## What "Docomo phonebook" actually is

| Package | Path | Role |
|---|---|---|
| `com.sonyericsson.android.socialphonebook` | `/system/priv-app/Phonebook/Phonebook.apk` | Sony social phonebook, the Docomo-branded Contacts/Phonebook app |
| `com.sonyericsson.android.socialphonebook.product.res.overlay` | `/vendor/overlay/Phonebook-Overlay-275-docomo-release.apk` | Docomo-specific resource overlay |
| `com.sonyericsson.android.socialphonebook.res.overlay_305` | `/oem/overlay/...` | Phonebook resource overlay |
| `com.sonymobile.overlay.socialphonebook` | `/vendor/overlay/PhonebookRuntimeOverlay` | Phonebook runtime overlay |
| `com.sonyericsson.android.contactpicker3` | `/system/app/SemcContactPicker2.3` | Sony contact picker |
| `com.nttdocomo.android.socialphonebook` | — | Docomo phonebook, hidden earlier |

The protected set in [debloat.md](debloat.md#protected-set-never-remove) lists
`phonebook`, `simcontacts`, and "all resource overlays". Those rules were
written for irreversible `pm uninstall`; with reversible `pm hide` they can be
tested safely — see [trigger-batch-revisited.md](trigger-batch-revisited.md).

## Why this one needs a functional check, not just a boot check

`dumpsys package` showed `socialphonebook` was the **preferred** handler for
several contact/dial intents:

```
Selected from:
  com.sonyericsson.android.socialphonebook/.activities.SocialPhonebookActivity
  com.android.contacts/.activities.PeopleActivity
Action: "com.android.contacts.action.LIST_ALL_CONTACTS"
...
Selected from:
  com.sonyericsson.android.socialphonebook/.DialerEntryActivity
  com.android.dialer/.DialtactsActivity
Action: "android.intent.action.DIAL"
```

This is the same shape as the HOME chooser problem in
[launcher.md](launcher.md): hiding a preferred component can leave a chooser
or a broken entry even though `boot=1 ui=1 home=4` all look fine. The
difference here is that AOSP fallbacks exist and are complete
(`com.android.contacts`, `com.android.dialer`,
`com.android.providers.contacts`), so resolution can move to them cleanly.
The package also has no `ContentProvider`, is not `PERSISTENT`, and the
`socialphonebook.api` framework library is used only by the package itself.

## Procedure (both batches reboot-verified)

```sh
# 1. Hide the preferred phonebook app alone.
./scripts/hide-batch.sh phonebook.txt
./scripts/reboot-verify.sh

# 2. Verify resolution moved to AOSP, and no chooser appeared.
adb shell dumpsys package | grep -A3 'LIST_ALL_CONTACTS'
adb shell dumpsys window | grep mFocusedApp
adb shell am start -a android.intent.action.DIAL
# expect com.android.dialer/.DialtactsActivity

# 3. Hide the now-orphaned Docomo overlays and contact picker.
./scripts/hide-batch.sh phonebook-remnants.txt
./scripts/reboot-verify.sh
```

After step 1, `dumpsys package` resolved `LIST_ALL_CONTACTS` to
`com.android.contacts/.activities.PeopleActivity` and `DIAL` to
`com.android.dialer/.DialtactsActivity`, with no `ResolverActivity`.
`am start -a android.intent.action.DIAL` launched the dialer; the
`com.android.contacts` process was alive; `fatal=0` after both batches.
A screenshot confirmed the lockscreen/SystemUI was intact.

## Kept (core phone functionality)

`com.android.contacts`, `com.android.dialer`,
`com.android.providers.contacts` and its overlays,
`com.google.android.syncadapters.contacts`, `com.sonyericsson.simcontacts`
(shares the phonebook UID, still used for SIM contacts),
`com.sonymobile.providers.topcontacts`, and
`com.sonymobile.advancedwidget.topcontacts` (shares the launcher UID).

## Verified final state

```
visible=263   hidden=150   total=413
boot=1  ui=1  home=4  running_svc=73  fatal=0
dialer: com.android.dialer/.DialtactsActivity
contacts: com.android.contacts/.activities.PeopleActivity
uptime 155s -> 190s (6 samples, monotonic)
uid=0(root) gid=0(root) context=u:r:shell:s0
hidden-packages.txt: identical SHA-1 in repo / host / NAS / device
device restore-all.sh: 150 pm unhide lines, sh -n passes
```

Five phonebook-related packages are now in the hidden list.
