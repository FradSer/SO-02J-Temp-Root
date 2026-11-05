/* Kick a Sony S1 Flashmode device (0fce:adde) out of flashmode so it boots.
 * Build: gcc -O2 -Wall -o flashoff flashoff.c
 * Run on a Linux host with USB passthrough.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/ioctl.h>
#include <linux/usbdevice_fs.h>
#include <linux/usb/ch9.h>

int main(void) {
    DIR *bd = opendir("/dev/bus/usb");
    if (!bd) { printf("no /dev/bus/usb\n"); return 1; }
    struct dirent *de;
    char bus[256], dev[256];
    int fd = -1;
    while ((de = readdir(bd))) {
        if (de->d_name[0] == '.') continue;
        snprintf(bus, sizeof bus, "/dev/bus/usb/%s", de->d_name);
        DIR *dd = opendir(bus);
        if (!dd) continue;
        struct dirent *de2;
        while ((de2 = readdir(dd))) {
            if (de2->d_name[0] == '.') continue;
            snprintf(dev, sizeof dev, "%s/%s", bus, de2->d_name);
            int f = open(dev, O_RDWR);
            if (f < 1) continue;
            struct usb_device_descriptor d;
            if (read(f, &d, 18) == 18 &&
                d.idVendor == 0x0fce && d.idProduct == 0xadde) {
                fd = f;
                printf("found %s vid=%04x pid=%04x\n", dev, d.idVendor, d.idProduct);
                break;
            }
            close(f);
        }
        closedir(dd);
        if (fd >= 0) break;
    }
    closedir(bd);
    if (fd < 0) { printf("device not in flashmode (0fce:adde)\n"); return 1; }

    int ifc = 0;
    if (ioctl(fd, USBDEVFS_CLAIMINTERFACE, &ifc) != 0) { perror("claim"); return 1; }

    /* S1 command: 4-byte opcode 0x04 (CMD_FLASHMODE_OFF) + FLAG3 + len 0 + xor checksum +7.
     * xflasher: memcpy(command, CMD_FLASHMODE_OFF, 4); FLAG3 = 00 00 00 03; len = 0.
     * Checksum = xor of first 12 bytes + 7.
     */
    unsigned char cmd[13] = {0,0,0,4, 0,0,0,3, 0,0,0,0, 0};
    int m = 0;
    for (int i = 0; i < 12; ++i) m ^= cmd[i];
    cmd[12] = (m + 7) & 0xff;

    struct usbdevfs_bulktransfer bulk;
    memset(&bulk, 0, sizeof bulk);
    bulk.ep = 0x01; /* EP_OUT */
    bulk.len = sizeof cmd;
    bulk.data = cmd;
    bulk.timeout = 5000;
    int n = ioctl(fd, USBDEVFS_BULK, &bulk);
    printf("bulk write rc=%d errno=%s\n", n, n < 0 ? strerror(errno) : "ok");
    close(fd);
    printf("FLASHOFF_SENT\n");
    return n < 0 ? 1 : 0;
}
