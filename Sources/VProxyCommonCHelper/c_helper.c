#if defined(__linux__)
#define _GNU_SOURCE
#else
#include <pthread.h>
#endif

#include <unistd.h>
#include <inttypes.h>
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

uint64_t swvs_get_tid(void) {
#if defined(__linux__)
    return gettid();
#else
    uint64_t tid;
    pthread_threadid_np(NULL, &tid);
    return tid;
#endif
}
