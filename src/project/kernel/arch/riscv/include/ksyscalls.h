#ifndef __KSYSCALLS_H__
#define __KSYSCALLS_H__

#include <stddef.h>

struct pt_regs;

long sys_read(unsigned fd, char *buf, size_t count);
long sys_write(unsigned fd, const char *buf, size_t count);
long sys_getpid(void);
long sys_clone(struct pt_regs *regs);

#endif
