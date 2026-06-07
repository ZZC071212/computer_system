#include <syscalls.h>
#include <unistd.h>
#include <stdint.h>

ssize_t read(int fd, void *buf, size_t count) {
  register long a0 asm("a0") = fd;
  register long a1 asm("a1") = (long)buf;
  register long a2 asm("a2") = (long)count;
  register long a7 asm("a7") = __NR_read;

  asm volatile("ecall"
               : "+r"(a0)
               : "r"(a1), "r"(a2), "r"(a7)
               : "memory");
  return (ssize_t)a0;
}

pid_t getpid(void) {
  register long a0 asm("a0");
  register long a7 asm("a7") = __NR_getpid;

  asm volatile("ecall" : "=r"(a0) : "r"(a7) : "memory");
  return (pid_t)a0;
}

pid_t fork(void) {
  register long a0 asm("a0");
  register long a7 asm("a7") = __NR_clone;

  asm volatile("ecall" : "=r"(a0) : "r"(a7) : "memory");
  return (pid_t)a0;
}

ssize_t write(int fd, const void *buf, size_t count) {
  register long a0 asm("a0") = fd;
  register long a1 asm("a1") = (long)buf;
  register long a2 asm("a2") = (long)count;
  register long a7 asm("a7") = __NR_write;

  asm volatile("ecall"
               : "+r"(a0)
               : "r"(a1), "r"(a2), "r"(a7)
               : "memory");
  return (ssize_t)a0;
}
