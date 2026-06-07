#include <ksyscalls.h>
#include <private_kdefs.h>
#include <proc.h>
#include <sbi.h>

static uint64_t kernel_buf_pa(const void *buf) {
  uint64_t addr = (uint64_t)buf;
  return addr >= VM_START ? addr - PA2VA_OFFSET : addr;
}

static long console_write(const char *buf, size_t count) {
  sbi_ecall(0x4442434e, 0, count, kernel_buf_pa(buf), 0, 0, 0, 0);
  return (long)count;
}

long sys_read(unsigned fd, char *buf, size_t count) {
  if (fd != 0 || buf == 0) {
    return -1;
  }

  size_t done = 0;
  while (done < count) {
    char c = 0;
    struct sbiret ret = sbi_ecall(0x4442434e, 1, 1, kernel_buf_pa(&c), 0, 0, 0, 0);
    if ((long)ret.error < 0 || ret.value == 0) {
      break;
    }
    if (c == '\r') {
      c = '\n';
    }
    buf[done++] = c;
    if (c == '\n') {
      break;
    }
  }

  return (long)done;
}

long sys_write(unsigned fd, const char *buf, size_t count) {
  if ((fd != 1 && fd != 2) || buf == 0) {
    return -1;
  }

  char chunk[64];
  size_t done = 0;
  while (done < count) {
    size_t n = count - done;
    if (n > sizeof(chunk)) {
      n = sizeof(chunk);
    }
    for (size_t i = 0; i < n; ++i) {
      chunk[i] = buf[done + i];
    }
    console_write(chunk, n);
    done += n;
  }

  return (long)count;
}

long sys_getpid(void) {
  return (long)current->pid;
}

long sys_clone(struct pt_regs *regs) {
  return do_fork(regs);
}//转发到proc.c中的do_fork函数实现
