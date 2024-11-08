#include <time.h>

void swvs_timefmt(char* buf) {
    time_t rawtime;
    struct tm *timeinfo;
    time(&rawtime);
    timeinfo = localtime(&rawtime);

    int bufsz = sizeof("2024-11-06 21:45:31");
    strftime(buf, bufsz, "%Y-%m-%d %H:%M:%S", timeinfo);
    buf[bufsz - 1] = '\0';
}
