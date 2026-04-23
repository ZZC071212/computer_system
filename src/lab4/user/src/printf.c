#include <stdio.h>
#include <unistd.h>

static int printf_syscall_write(FILE *restrict fp, const void *restrict buf, size_t len) {
  // TODO for you:
  // add fd to the FILE struct and make this look better :)
  // you can just by the way implement the fileno function and use it here
  (void)fp;
  return (int)write(STDOUT_FILENO, buf, len);
}

int printf(const char *restrict fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  int ret = vfprintf(stdout, fmt, ap);
  va_end(ap);
  return ret;
}

FILE __iob[3] = {
    {},                              // stdin
    {.write = printf_syscall_write}, // stdout
    {},                              // stderr
};
