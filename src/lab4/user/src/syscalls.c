#include <syscalls.h>
#include <unistd.h>
#include <stdint.h>

pid_t getpid(void) {
  pid_t ret;
  asm volatile("li a7, %1\n\t"
               "ecall\n\t"
               "mv %0, a0\n\t"
               : "=r"(ret)
               : "i"(__NR_getpid)
               : "a0", "a7", "memory");
  return ret;
}

ssize_t write(int fd, const void *buf, size_t count) {
#error Not yet implemented
  return -1;
}
