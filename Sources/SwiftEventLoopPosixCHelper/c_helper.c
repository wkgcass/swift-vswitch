#include "c_helper.h"
#include <errno.h>
#include <sys/ioctl.h>
#include <pthread.h>
#include <unistd.h>

ssize_t writeWithErrno(int fd, const void* buf, size_t count, int* err) {
    ssize_t n = write(fd, buf, count);
    if (n < 0) {
        *err = errno;
    }
    return n;
}

ssize_t readWithErrno(int fd, void* buf, size_t count, int* err) {
    ssize_t n = read(fd, buf, count);
    if (n < 0) {
        *err = errno;
    }
    return n;
}

int connectWithErrno(int sockfd, const struct sockaddr* addr, socklen_t addrlen, int* err) {
    int e = connect(sockfd, addr, addrlen);
    if (e < 0) {
        *err = errno;
    }
    return e;
}

int acceptWithErrno(int sockfd, struct sockaddr* addr, socklen_t* addrlen, int* err) {
    int fd = accept(sockfd, addr, addrlen);
    if (fd < 0) {
        *err = errno;
    }
    return fd;
}

ssize_t recvfromWithErrno(int sockfd, void* buf, size_t len, int flags, struct sockaddr* src_addr, socklen_t* addrlen, int* err) {
    ssize_t n = recvfrom(sockfd, buf, len, flags, src_addr, addrlen);
    if (n < 0) {
        *err = errno;
    }
    return n;
}

ssize_t sendtoWithErrno(int sockfd, const void* buf, size_t len, int flags, const struct sockaddr* dest_addr, socklen_t addrlen, int* err) {
    ssize_t n = sendto(sockfd, buf, len, flags, dest_addr, addrlen);
    if (n < 0) {
        *err = errno;
    }
    return n;
}

int swvs_configureBlocking(int fd, int blocking) {
    int nb;
    if (blocking) {
        nb = 0;
    } else {
        nb = 1;
    }
    return ioctl(fd, FIONBIO, &nb);
}

void swvs_start_thread(swvs_thread_t* thread, swvs_pthread_runnable runnable, void* ud) {
    pthread_create(&thread->thread, NULL, runnable, ud);
}

#ifdef __linux__
int swvs_set_core_affinity(int64_t mask, int* err) {
    pthread_t current = pthread_self();
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    for (int i = 0; i < 64; ++i) {
        int bit = (mask >> i) & 1;
        if (bit) {
            CPU_SET(i, &cpuset);
        }
    }
    int ret = pthread_setaffinity_np(current, sizeof(cpu_set_t), &cpuset);
    if (ret != 0) {
        *err = errno;
    }
    return ret;
}
#endif
