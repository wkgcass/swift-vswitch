#ifndef _C_HELPER_
#define _C_HELPER_

#define _GNU_SOURCE

#include <unistd.h>
#include <sys/socket.h>
#include <inttypes.h>
#include <pthread.h>

typedef struct {
    pthread_t thread;
} swvs_thread_t;
typedef void* (*swvs_pthread_runnable)(void*);

ssize_t writeWithErrno(int fd, const void* buf, size_t count, int* err);
ssize_t readWithErrno (int fd,       void* buf, size_t count, int* err);
int connectWithErrno(int sockfd, const struct sockaddr* addr, socklen_t  addrlen, int* err);
int acceptWithErrno (int sockfd,       struct sockaddr* addr, socklen_t* addrlen, int* err);
ssize_t recvfromWithErrno(int sockfd,       void* buf, size_t len, int flags,       struct sockaddr* src_addr,  socklen_t* addrlen, int* err);
ssize_t sendtoWithErrno  (int sockfd, const void* buf, size_t len, int flags, const struct sockaddr* dest_addr, socklen_t  addrlen, int* err);

int swvs_configureBlocking(int fd, int blocking);
void swvs_start_thread(swvs_thread_t* thread, swvs_pthread_runnable runnable, void* ud);
#ifdef __linux__
int swvs_set_core_affinity(int64_t mask, int* err);
#endif

#endif // _C_HELPER_
