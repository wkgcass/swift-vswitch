#include <inttypes.h>

struct swvs_tap_info {
    char dev_name[16];
    int  fd;
};

int swvs_open_tap(const char* dev_chars, uint8_t is_tun, struct swvs_tap_info* ret);
