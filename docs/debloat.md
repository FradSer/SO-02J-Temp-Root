# Debloat notes (SO-02J, 34.1.B.0.336)

## Method

`pm uninstall -k --user 0 <package>` performed from an ordinary `adb shell`.
This does **not** need root — the shell uid can remove a package for user 0.
The APK stays in its read-only `/system` or `/oem` location; the package
appears in `pm list packages -u` but not in `pm list packages`.

`pm disable-user --user 0` is **not** usable here: it returns
`SecurityException: Permission Denial: attempt to change component state
from uid=2000`. Running `pm` inside the escalated shell also fails
(`Aborted (core dumped)`), so uninstall is the workable route.

## Reversibility warning

This build has no `cmd` binary and no `install-existing` command.
`pm install -r <system apk>` prints a path but does not re-register the
package. Rebooting does not restore per-user uninstalls either.

**The only reliable restore is reflashing the stock FTF** in S1 Flashmode
(see [flashing.md](flashing.md)), which needs physical button access.

## Protected set (never remove)

Removing any of these caused or would cause a SystemUI crash loop / black
screen / boot failure. This was observed first-hand in this project:
uninstalling `com.sonymobile.superstamina` made SystemUI crash in a loop
because `PowerNotificationWarnings` registers a content observer on its
provider. Recovery required a full reflash.

- `com.android.systemui`, `com.android.settings`, `com.android.phone`,
  all `com.android.providers.*`, `com.android.server.*`
- launcher: `com.sonyericsson.home` (and `com.sonymobile.simplehome`)
- IME: `com.touchtype.swiftkey`, `com.sonymobile.pobox*`,
  `com.sonyericsson.textinput.chinese`
- telephony/messaging: dialer, contacts, incallui, conversations,
  phonebook, simcontacts, wappush, omacp
- `com.sonymobile.superstamina`, `com.sonyericsson.android.servicemenu`,
  `com.sonymobile.xperiaservices`, `com.sonymobile.getset.priv`,
  `com.sonymobile.deviceconfigtool`
- **all resource overlays** (`*.res.overlay*`, `*.product.res.overlay*`,
  `/vendor/overlay`, `/oem/overlay`) — referenced by framework resources
- **all `*.permission` packages** and permission-defining APKs
- low-level services: `com.sonymobile.wifi`, `com.sonymobile.psrvc`,
  `com.sonymobile.rcahandler`, `com.sonymobile.sso`,
  `com.sonymobile.runtimeskinning.core`, `com.quicinc.cne.CNEService`,
  FOTA / device-security / credential / simlock services
- WebView, Play services, Play Store, `com.google.android.gsf`

### Why `com.sonymobile.wifi` is kept

It is **not** a duplicate of an AOSP WiFi app. AOSP's WiFi stack lives in
`framework`/`system_server`, not in an APK. `SomcWifiService` is Sony's
actual WiFi service implementation:

```
flags=[ SYSTEM HAS_CODE PERSISTENT ]   privateFlags=[ PRIVILEGED ]
sharedUser=android.uid.system/1000
Service Resolver Table:
  com.sonymobile.wifi.ISomcWifiManager        -> .internal.SomcWifiService
  com.sonymobile.wifi.p2p.ISomcWifiP2pManager -> .internal.SomcWifiService
  com.sonymobile.wifi.IWifiDebugManager       -> .internal.SomcWifiService
usesLibraries: com.sonymobile.wifi.api_1 -> /system/framework/com.sonymobile.wifi_impl.jar
```

Other packages declare `com.sonymobile.wifi.api_1` as a `usesLibrary`.
Removing the provider of that library makes framework class loading fail.
The other WiFi-named package, `com.sonyericsson.settings.wifi`, is only the
hotspot settings UI.

## Active device admin

`com.nttdocomo.android.remotelock` cannot be uninstalled while it is an
enabled device admin:

```
Enabled Device Admins (User 0):
  com.nttdocomo.android.wipe/.DmDeviceAdminReceiver
  com.nttdocomo.android.remotelock/.DmDeviceAdminReceiver
```

`pm uninstall` returns `DELETE_FAILED_DEVICE_POLICY_MANAGER` regardless of
uid 0. `dpm remove-active-admin --user 0 <component>` removes it from the
admin list, but PackageManager keeps a cached device-policy state until a
reboot — and a reboot drops the memory-only root. Leave this package alone
unless you are prepared to reflash.

## Post-debloat state observed

```
installed packages: 413 -> 226
SystemUI alive, sys.boot_completed=1, visible layers=7
running init services=73, AVC denials=0, crash lines=0
```

`scripts/debloat.sh` enforces the protected set and runs a health check
every 5 removals, stopping immediately if SystemUI, boot, or the launcher
disappears. Run `scripts/monitor-load.sh load` and
`scripts/monitor-load.sh health` afterwards to sample system load.
