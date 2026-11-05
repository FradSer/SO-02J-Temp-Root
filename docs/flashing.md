# Flashing (S1 Flashmode downgrade)

The device has a locked bootloader (`Bootloader unlock allowed: No`), so no
fastboot image can be flashed. Sony's S1 Flashmode is a separate, signed,
pre-boot protocol that accepts stock `.sin` files without unlocking.

| Item | Value |
|---|---|
| USB VID:PID in Flashmode | `0fce:adde` |
| How to enter | Power off, hold **Volume Down**, plug USB, wait for a solid green LED |
| Tool | `xflasher` v23 (munjeni) for pre-2017 Xperia, or Flashtool |
| Protocol | Linux `usbfs` bulk URBs on `EP 0x81 IN` / `0x01 OUT`, 512-byte packets |

`newflasher` is **not** usable here: it hardcodes PID `0xb00b` for 2017+
devices (`GordonGate` protocol). `xflasher` uses Linux usbfs ioctls, so it
must run on a Linux host. It can run in a Linux VM with USB passthrough if
the phone is physically connected to a macOS host.

## Prepare the payload directory

Unpack the FTF into a working directory, then:

```sh
mkdir TA_EXCLUDED
find . -type f -name '*.ta' -not -path '*/TA_EXCLUDED/*' -exec mv {} TA_EXCLUDED/ \;
```

Keep `xflasher` (or `loader.sin`/`max_p` handling) and all 19 `.sin` files.
Do **not** place a generic `loader.sin` in this directory: this device has
its own S1 boot and rejects a generic loader with
`;VER="1299-4841 S1_Boot_MSM8956_LA1.0.1_78-A"` instead of an ACK. With no
`loader.sin` present, `xflasher` generates a script whose first command is
`noloader` (handshake only, no upload).

## Generated command pattern

`xflasher` (run with no arguments) writes `xflasher.sh`, whose shape is:

```sh
./xflasher loader.sin 0 0 0FCE ADDE 0 0        # change to: noloader
./xflasher partition.sin 0 0 0FCE ADDE 0 0    # one .sin per invocation
./xflasher kernel.sin    0 0 0FCE ADDE 0 0
...
./xflasher userdata.sin  0 0 0FCE ADDE 0 0
./xflasher 0 0 0 0FCE ADDE 1 0               # boot delivery: SKIP
```

- First command must be `noloader` for this device. It consumes the S1 boot
  greeting and records `MAX_PKT_SZ` / OTP data into `max_p` and `btinf`, but
  uploads nothing.
- Every later command writes exactly one `.sin` (`argv[1]` is the file).
- **Skip the boot delivery step.** `boot_delivery.xml` references `*.sin`
  names while this FTF ships `*.sinb` bundles, and it expects the XML under
  `boot/`. Flashing bootloader bundles is the classic way to hard-brick this
  platform. Keeping the existing S1 boot works across the downgrade.
- **Never flash any `.ta` file.**

`max_p` on this device was `00400000` (4 MB). `system.sin` is ~2.4 GB, so it
is split into ~600 chunks; allow generous per-file timeouts.

## Verification after flashing

```sh
adb shell getprop ro.build.display.id      # 34.1.B.0.336
adb shell getprop ro.build.version.release # 6.0.1
adb shell uname -r                         # 3.10.84-perf-...
```

Expect a long first boot (10+ minutes). If the device hangs at the logo, go
back to Flashmode and re-flash; this chain does not touch the bootloader, so
recovery is possible.

## Pitfalls observed

- `dirtycow`-style page-cache overlays do not survive a reboot — that is a
  feature, not a bug, for the root step.
- USB passthrough adds latency; bulk IN/OUT still works, but do not detach the
  cable mid-flash.
- A solid green LED (Flashmode, Volume Down) is different from a blue LED
  (fastboot, Volume Up). Fastboot cannot be used with this locked bootloader.
