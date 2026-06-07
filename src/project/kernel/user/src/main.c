#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// define some tests
#define PFH1 1001
#define PFH2 1002
#define FORK1 1101
#define FORK2 1102
#define FORK3 1103
#define FORK4 1104
#define SHELL 1150

#if defined(USER_MAIN) && !(USER_MAIN > 1000 && USER_MAIN < 1200)
#warning "Invalid definition of USER_MAIN"
#undef USER_MAIN
#endif

#ifndef USER_MAIN
// 你可以修改这一行来提供代码高亮
#define USER_MAIN PFH1
#endif

#define DELAY_TIME 1247

static void delay(unsigned long ms) {
  volatile unsigned long ticks = ms * 128;
  while (ticks--) {
    asm volatile("" ::: "memory");
  }
}

#if USER_MAIN == PFH1

int main(void) {
  register const void *const sp asm("sp");

  while (1) {
    printf("\x1b[44m[U]\x1b[0m [PID = %d, sp = %p]\n", getpid(), sp);
    delay(DELAY_TIME);
  }
}

#elif USER_MAIN == PFH2

const char *const xdigits = "0123456789abcdef";
char space[0x2000] __attribute__((aligned(0x1000)));
size_t i;

int main(void) {
  while (1) {
    i = 0;
    printf("\x1b[44m[U]\x1b[0m [PID = %d] ", getpid());
    while (i < sizeof(space)) {
      space[i] = xdigits[i % 16];
      printf("\x1b[4%cm%c\x1b[0m", xdigits[rand() % 8], space[i]);
      i++;
      delay(1);
    }
    printf("\n");
  }
}

#elif USER_MAIN == FORK1

int var = 0;

int main(void) {
  pid_t pid = fork();
  const char *ident = pid ? "PARN" : "CHLD";

  while (1) {
    printf("\x1b[44m[U-%s]\x1b[0m [PID = %d] var = %d\n", ident, getpid(), var++);
    delay(DELAY_TIME / 2 + rand() % DELAY_TIME);
  }
}

#elif USER_MAIN == FORK2

int var = 0;
char space[0x2000] __attribute__((aligned(0x1000)));

int main(void) {
  for (int i = 0; i < 3; i++) {
    printf("\x1b[44m[U]\x1b[0m [PID = %d] var = %d\n", getpid(), var++);
    delay(DELAY_TIME);
  }

  memcpy(&space[0x1000], "ZJU Sys3 Lab5", 14);

  pid_t pid = fork();
  const char *ident = pid ? "PARN" : "CHLD";

  printf("\x1b[44m[U-%s]\x1b[0m [PID = %d] Message: %s\n", ident, getpid(), &space[0x1000]);
  while (1) {
    printf("\x1b[44m[U-%s]\x1b[0m [PID = %d] var = %d\n", ident, getpid(), var++);
    delay(DELAY_TIME / 2 + rand() % DELAY_TIME);
  }
}

#elif USER_MAIN == FORK3

int var = 0;

int main(void) {
  printf("\x1b[44m[U]\x1b[0m [PID = %d] var = %d\n", getpid(), var++);
  fork();
  fork(); // multiple references to one page

  printf("\x1b[44m[U]\x1b[0m [PID = %d] var = %d\n", getpid(), var++);
  fork();

  while (1) {
    printf("\x1b[44m[U]\x1b[0m [PID = %d] var = %d\n", getpid(), var++);
    delay(DELAY_TIME / 2 + rand() % DELAY_TIME);
  }
}

#elif USER_MAIN == FORK4

#define LARGE 1000

int var = 0;
long bigarr[LARGE] __attribute__((aligned(0x1000))) = {};

int fib(int times) {
  if (times <= 2) {
    return 1;
  } else {
    return fib(times - 1) + fib(times - 2);
  }
}

const char *suffix(int num) {
  num %= 100;
  int i = num % 10;
  if (i == 1 && num != 11) {
    return "st";
  } else if (i == 2 && num != 12) {
    return "nd";
  } else if (i == 3 && num != 13) {
    return "rd";
  } else {
    return "th";
  }
}

int main(void) {
  for (int i = 0; i < LARGE; i++) {
    bigarr[i] = 3 * i + 1;
  }

  pid_t pid = fork();
  const char *ident = pid ? "PARN" : "CHLD";
  printf("\x1b[44m[U]\x1b[0m fork returns %d\n", pid);

  while (1) {
    var = 0;
    while (var < LARGE) {
      printf("\x1b[44m[U-%s]\x1b[0m [PID = %d] the %d%s fibonacci number is %d and "
             "the %d%s number in the big array is %ld\n",
             ident, getpid(), var, suffix(var), fib(var), LARGE - 1 - var, suffix(LARGE - 1 - var),
             bigarr[LARGE - 1 - var]);
      var++;
      delay(100);
    }
  }
}

#elif USER_MAIN == SHELL

static int shell_streq(const char *a, const char *b) {
  while (*a && *b && *a == *b) {
    a++;
    b++;
  }
  return *a == 0 && *b == 0;
}

static int shell_starts_with(const char *s, const char *prefix) {
  while (*prefix) {
    if (*s++ != *prefix++) {
      return 0;
    }
  }
  return 1;
}

static char *shell_skip_space(char *s) {
  while (*s == ' ' || *s == '\t') {
    s++;
  }
  return s;
}

static void shell_readline(char *buf, size_t size) {
  if (size == 0) {
    return;
  }
  ssize_t n = read(STDIN_FILENO, buf, size - 1);
  if (n < 0) {
    n = 0;
  }
  buf[n] = 0;
  for (ssize_t i = 0; i < n; i++) {
    if (buf[i] == '\r' || buf[i] == '\n') {
      buf[i] = 0;
      break;
    }
  }
}

static void shell_tlb_demo(void) {
  static volatile uint64_t page[512] __attribute__((aligned(0x1000)));
  uint64_t sum = 0;

  for (int round = 0; round < 64; round++) {
    for (int i = 0; i < 512; i += 8) {
      page[i] = (uint64_t)(round + i);
      sum += page[i];
    }
  }
  printf("tlb demo touched one hot page, checksum = %lu\n", sum);
}

static void shell_help(void) {
  printf("commands: help, pid, echo <text>, fork, tlb, exit\n");
}

int main(void) {
  char line[96];

  printf("\n[xpart-shell] read syscall + simple shell ready\n");
  shell_help();

  while (1) {
    printf("$ ");
    shell_readline(line, sizeof(line));
    printf("%s\n", line);

    char *cmd = shell_skip_space(line);
    if (*cmd == 0) {
      continue;
    }

    if (shell_streq(cmd, "help")) {
      shell_help();
    } else if (shell_streq(cmd, "pid")) {
      printf("pid = %d\n", getpid());
    } else if (shell_starts_with(cmd, "echo ")) {
      printf("%s\n", shell_skip_space(cmd + 5));
    } else if (shell_streq(cmd, "fork")) {
      pid_t pid = fork();
      if (pid == 0) {
        printf("child shell task alive, pid = %d\n", getpid());
        while (1) {
          asm volatile("" ::: "memory");
        }
      }
      printf("parent forked child pid = %d\n", pid);
    } else if (shell_streq(cmd, "tlb")) {
      shell_tlb_demo();
    } else if (shell_streq(cmd, "exit")) {
      printf("shell demo done\n");
      while (1) {
        asm volatile("" ::: "memory");
      }
    } else {
      printf("unknown command: %s\n", cmd);
    }
  }
}

#endif
