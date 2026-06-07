#ifndef __UNISTD_H__
#define __UNISTD_H__

#include <stddef.h>

#define STDIN_FILENO 0
#define STDOUT_FILENO 1
#define STDERR_FILENO 2

typedef int pid_t;
typedef long ssize_t;

ssize_t read(int fd, void *buf, size_t count);
ssize_t write(int fd, const void *buf, size_t count);
pid_t getpid(void);
pid_t fork(void);

#endif
