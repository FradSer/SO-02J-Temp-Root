# Desktop pet, overseas services, and the large Docomo cleanup

Three follow-up passes after [launcher.md](launcher.md). All use reversible
`pm hide` with a real reboot verification after every batch (see
[hide-debloat.md](hide-debloat.md)).

## The desktop pet

The red-hatted character and stacked coins on the home screen were **not** a
launcher widget. `dumpsys window windows` showed an overlay owned by uid 10279
with `appop=SYSTEM_ALERT_WINDOW`:

```
mOwnerUid=10279 mShowToOwnerOnly=true package=com.nttdocomo.android.mascot
```

Two processes were running (`com.nttdocomo.android.mascot` and its
`:monitorprocess`). It survived the launcher swap precisely because it draws
on top of any home screen. Hiding that one package removed the overlay;
`ps | grep -c mascot` went to 0 and a screenshot confirmed a clean desktop.

This is worth checking whenever something stays on screen after a launcher
change: `dumpsys appwidget` lists widgets, but an overlay pet needs
`dumpsys window windows` + `appop=SYSTEM_ALERT_WINDOW`.

## Overseas (non-Japanese) services

The user meant the Google/Facebook/foreign vendor layer, as opposed to the
Docomo layer. Two batches, each reboot-verified:

- `com.facebook.appmanager`, `com.facebook.system`,
  `com.android.partnerbrowsercustomizations.chromeHomepage`,
  `com.mobileselect.somcprein`, `com.swiftkey.swiftkeyconfigurator`,
  `com.google.android.feedback`, `com.google.android.partnersetup`.
- `com.google.android.apps.maps`, `com.google.android.calendar`,
  `com.google.android.tts`, `com.google.android.googlequicksearchbox`.

Hiding `googlequicksearchbox` removed the Google search bar widget from the
home screen; no broken widget remained and the launcher stayed healthy.

**Kept deliberately:** Play services (`com.google.android.gms`, 300 declared
service actions), Play Store, WebView, GSF / GSF login, setup wizard
(`PERSISTENT`), package installer, backup transport, config updater, all
`com.qti.*` / `com.qualcomm.*` (shared `android.uid.system` / `uid.phone`
radio stack), SwiftKey IME itself, and all resource overlays.

## Large Docomo service cleanup

The classifier initially reported "0 deletable" because it treated the
**count of service actions a package declares** as framework binding. That is
wrong: an action like `com.nttdocomo.android.areamail.z9` or
`...iconcier_contents.IAnalyzeMemoService` is the package's own private
service, not a framework dependency. Only shared UIDs, `PERSISTENT`,
providers, and the seven explicitly Binder-bound services are hard signals.

Two batches (12 packages), each reboot-verified:

- `areamail`, `iconcier_contents`, `pf.dcmwappush`, `screenlockservice`,
  `mediaplayer`, `decoemojimanager_docomo`, `databackup`, `schedulememo`,
  `saigaiban`.
- `devicehelp` (AccessibilityService + NotificationListenerService),
  `accountauthenticator` (AccountAuthenticator + SyncAdapter), `fs1seg`
  (1seg TV, own shared UID).

These three carried system-facing interfaces but hid cleanly.

### What remains and why

After this pass, 22 Japanese-branded packages are still visible, all in a
protected category:

| Category | Count | Examples |
|---|---|---|
| Bootloop trigger batch | 11 | `felicanetworks.mfc/mfm/mfs/mfw.a.boot`, `atf`, `apnsw`, `accountwipe`, `idmanager`, `settings.lac`, `rwpushcontroller` |
| Resource overlays | 3 | `osv.res.overlay_305`, `servicemenu.product.res.overlay.docomo`, `superstamina.docomo.res.overlay` |
| Shared system/NFC UID | 3 | `felicaremotelock`, `tapandpay`, `docomo.settings` |
| Explicitly Binder-bound | 3 | `lac`, `phonemotion`, `osaifu.tsmproxy` |
| Device admins | 2 | `wipe` (active), `remotelock` |

`com.nttdocomo.android.remotelock` was attempted separately. `pm hide`
returned `new hidden state: false` because it is an enabled device admin; the
script recorded `HIDE_FAIL`, did not add it to the rollback list, and left the
device unchanged. This is the same blocker that made
`pm uninstall` fail with `DELETE_FAILED_DEVICE_POLICY_MANAGER` earlier. It is
not worth forcing: disabling the admin needs a reboot, which drops the
memory-only root, and removing it gains nothing essential.

## Verified final state (historical snapshot of that pass)

```
visible=293   hidden=120   total=413
foreground HOME: com.sonyericsson.home/com.sonymobile.home.HomeActivity
boot=1  ui=1  home=4  running_svc=73  fatal=0
uptime 92s -> 127s (6 samples, monotonic)
uid=0(root) gid=0(root) context=u:r:shell:s0
hidden-packages.txt: identical SHA-1 in repo / host / NAS / device
device restore-all.sh: 120 pm unhide lines, sh -n passes
```

Screenshot after the pet removal shows the stock Xperia Home with no pet, no
Docomo launcher, and no Google search bar widget.
