# Xperia Lounge Japan: the icon is not the package

The user asked why **Xperia™ Lounge Japan** was still in the app drawer and
said that if it cannot be deleted, it must at least be hidden.

## Answer: the package was already hidden; the icon was a stale shortcut

`com.sonymobile.entrance` is the Xperia Lounge Japan app. Its APK contains
`res/drawable-*/drawer_xperia_lounge.png` and the literal `Lounge` label. It
had been hidden since an earlier pass, along with `com.sonymobile.gettoknowit`.
`pm list packages` did not list either of them. Yet a gift-box icon labelled
"Xperia™ Lounge Japan" still appeared on one app-drawer page.

**Hiding a package does not remove a shortcut already stored in the
launcher's database.** Xperia Home draws those entries as custom views, which
is also why `uiautomator dump` never exposed the label text — the screenshot
showed it while the UI dump reported no `lounge` node. Do not conclude from a
UI dump that an icon is gone; use a screenshot.

## What was done

1. Confirmed the real package by pulling `entrance.apk` and inspecting its
   resources, rather than guessing from the label.
2. Hid the only remaining visible Lounge-related package,
   `com.sonymobile.getmore` (a `PERSISTENT` GetMore/Xperia Tips service with
   its own provider). One batch, `REBOOT_VERIFY_PASS`, process count dropped
   to 0, `fatal=0`. The icon was **still** present afterwards.
3. Long-pressed the icon in the drawer. A red X appeared (edit mode). Tapping
   it produced an uninstall confirmation: "Do you want to uninstall this
   app?" with Cancel / Uninstall.
4. Tapped Uninstall. The drawer page then showed only Play Store and Settings,
   and the page indicator went from 3 pages to 2. A reboot confirmed the icon
   did not come back.

## Side effect found by checking the numbers

After the uninstall, `universe` went from 413 to **412** and `visible` from
243 to 241. Diffing `pm list packages -u` before and after showed the removed
package was **`com.sonyericsson.androidapp.sehome`** (Simple Home, a
`/data/app` package and a member of the old bootloop trigger batch). System
`priv-app` packages such as `entrance` and `getmore` were not actually
uninstalled — they remain present in `-u` and hidden. The launcher's uninstall
action resolved to a user-installed package on that page, not to the Lounge
app itself. This was harmless (Simple Home was already hidden and wanted
gone), but it is exactly the kind of change that should be detected by
comparing counts, not assumed.

## Rule

When a user says "an app is still there", distinguish three different things:

| Layer | How to check | Fix |
|---|---|---|
| Package visible | `pm list packages` | `pm hide --user 0 <pkg>` |
| Package present but hidden | `pm list packages -u` | already done; no action |
| Launcher shortcut / custom drawer entry | screenshot + long-press | remove via launcher edit mode |

`pm` commands cannot touch launcher database rows. A `pm clear` on the home
app would also work but resets the whole desktop layout, so the UI removal is
preferable.

## Verified final state

```
visible=241   hidden=171   universe=412
boot=1  ui=1  home=4  running_svc=73  fatal=0
uptime 117s -> 152s (6 samples, monotonic)
uid=0(root) gid=0(root) context=u:r:shell:s0
hidden-packages.txt: identical SHA-1 in repo / host / NAS / device
device restore-all.sh: 171 pm unhide lines, sh -n passes
Xperia Lounge Japan icon: absent from the app drawer after reboot
```
