#ifndef __KSYSCALLS_H__
#define __KSYSCALLS_H__

#include <stddef.h>

long sys_write(unsigned fd, const char *buf, size_t count);
long sys_getpid(void);

#endif
