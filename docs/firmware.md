# Firmware

Target firmware for the temporary root chain.

| Field | Value |
|---|---|
| Device | Sony Xperia X Compact, NTT Docomo (`SO-02J`), codename `kugo` |
| Platform | `Loire`, Qualcomm MSM8956 (Snapdragon 650), aarch64 |
| Build | `34.1.B.0.336` |
| Android | 6.0.1, SDK 23 |
| Kernel | `3.10.84-perf` |
| Security patch | 2016-07-01 |
| CDA / branding | `1305-8403` / `NTT DoCoMo JP` |
| FTF file | `SO-02J_34.1.B.0.336_1305-8403_R13B.ftf` |
| Size | 2,472,525,290 bytes |
| MD5 | `ac99dc8430040c3e8517eb2be009dcd1` |
| SHA1 | `6dd3cf8d4a9939a95afc9176cb31497f91534876` |

The 2016-07-01 patch level predates the Dirty COW (CVE-2016-5195) fix, which
is what makes the temporary root payload work on this build.

## Why downgrade

The device in this work arrived on `34.4.B.1.135` (Android 8.0, SPL
2018-10-01). That build has no known temporary-root exploit usable with a
locked bootloader, and its service menu reports
`Bootloader unlock allowed: No`. Downgrading to the 6.0.1 FTF restores the
CVE-2016-5195 window without touching the bootloader or the TA partition.

## Where to get it

Community-maintained archives of Japanese Xperia FTF files exist on the
Internet Archive (the `xperia-ftf-archive` / `xperia-firmware` items, under
`国内版Xperia/Xperia X Compact/`). Sony does not serve this build from its
own tools anymore. The FTF is a ZIP container; it contains Sony-signed `.sin`
files that the device will reject without a valid signature.

**Always verify the MD5/SHA1 above before flashing.** Do not use a file that
does not match. The FTF itself is not redistributed in this repository.

## FTF contents (relevant parts)

- 19 top-level `.sin` partitions: `partition`, `kernel`, `system`, `userdata`,
  `modem`, `oem`, `boot`-related, radio and logging images.
- `boot/` with 29 `.sinb` S1 bootloader bundles plus `boot_delivery.xml`.
- 7 `.ta` files (`auto-boot.ta`, `cust-reset.ta`, `master-reset.ta`, ...).
  **These are not flashed** — writing TA would destroy device-unique DRM keys.

`META-INF/MANIFEST.MF` confirms `version`, `device`, `cda`, `branding` and a
`noerase` list. Decode it with `unzip -p <ftf> META-INF/MANIFEST.MF`.

## Integrity check

```sh
md5sum SO-02J_34.1.B.0.336_1305-8403_R13B.ftf
# ac99dc8430040c3e8517eb2be009dcd1
sha1sum SO-02J_34.1.B.0.336_1305-8403_R13B.ftf
# 6dd3cf8d4a9939a95afc9176cb31497f91534876
unzip -t SO-02J_34.1.B.0.336_1305-8403_R13B.ftf | tail -1
# No errors detected in compressed data
```
