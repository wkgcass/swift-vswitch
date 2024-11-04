#include "c_helper.h"
#include <net/if.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>

#ifdef __linux__
#include <linux/if.h>
#include <linux/if_tun.h>
#elif defined(__APPLE__)
#include <sys/kern_control.h>
#include <net/if_utun.h>
#include <sys/sys_domain.h>
#endif

static inline int swvs_str_starts_with(const char* str, const char* prefix) {
    uint64_t prelen = strlen(prefix);
    uint64_t len = strlen(str);
    return len < prelen ? 0 : memcmp(prefix, str, prelen) == 0;
}

int swvs_open_tap(const char* dev_chars, uint8_t is_tun, struct swvs_tap_info* ret) {
    // the returned device name
    char dev_name[IFNAMSIZ];
    // fd for the tap char device
    int fd = 0;
    // prepare the ifreq object
    struct ifreq ifr;
    memset(&ifr, 0, sizeof(ifr));

#ifdef __linux__
    if ((fd = open("/dev/net/tun", O_RDWR)) < 0) {
        goto fail;
    }
    ifr.ifr_flags = 0;
    if (is_tun) {
        ifr.ifr_flags |= IFF_TUN;
    } else {
        ifr.ifr_flags |= IFF_TAP;
    }
    ifr.ifr_flags |= IFF_NO_PI;
    strncpy(ifr.ifr_name, dev_chars, IFNAMSIZ);
    ifr.ifr_name[IFNAMSIZ-1] = '\0';

    if (ioctl(fd, TUNSETIFF, (void *) &ifr) < 0) {
        goto fail;
    }

    strncpy(dev_name, ifr.ifr_name, IFNAMSIZ);
    dev_name[IFNAMSIZ-1] = '\0';
// end ifdef __linux__
#elif defined(__APPLE__)
    if (!is_tun) {
        return -1;
    }
    // use macos utun
    if (!swvs_str_starts_with(dev_chars, "utun")) {
        fprintf(stderr, "macOS tun devices must start with `utun`\n");
        return -1;
    }
    int utun = atoi(dev_chars + 4); // 4 for "utun"
    if (utun < 0) {
        fprintf(stderr, "tun devices must be utun{n} where n >= 0\n");
        return -1;
    }

    fd = socket(PF_SYSTEM, SOCK_DGRAM, SYSPROTO_CONTROL);
    if (fd < 0) {
        goto fail;
    }
    struct ctl_info ctlInfo;
    strlcpy(ctlInfo.ctl_name, UTUN_CONTROL_NAME, sizeof(ctlInfo.ctl_name));
    struct sockaddr_ctl sc;
    if (ioctl(fd, CTLIOCGINFO, &ctlInfo) == -1) {
        goto fail;
    }
    sc.sc_id = ctlInfo.ctl_id;
    sc.sc_len = sizeof(sc);
    sc.sc_family = AF_SYSTEM;
    sc.ss_sysaddr = AF_SYS_CONTROL;
    sc.sc_unit = utun + 1;
    if (connect(fd, (struct sockaddr*) &sc, sizeof(sc)) < 0) {
        goto fail;
    }
#endif

    strncpy(ret->dev_name, dev_name, IFNAMSIZ);
    ret->dev_name[IFNAMSIZ-1] = '\0';
    ret->fd = fd;
    return 0;
fail:
    fprintf(stderr, "failed to open tap/tun dev: %d(%s)\n", errno, strerror(errno));
    if (fd > 0) {
        close(fd);
    }
    return -1;
}
