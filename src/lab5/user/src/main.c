#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <inttypes.h>
#include <unistd.h>

// define some tests
#define PFH1 1001
#define PFH2 1002
#define FORK1 1101
#define FORK2 1102
#define FORK3 1103
#define FORK4 1104

#if defined(USER_MAIN) && !(USER_MAIN > 1000 && USER_MAIN < 1200)
#warning "Invalid definition of USER_MAIN"
#undef USER_MAIN
#endif

#ifndef USER_MAIN
// 你可以修改这一行来提供代码高亮
#define USER_MAIN PFH1
#endif

#define DELAY_TIME 1247

static uint64_t user_clock(void) {
  uint64_t ret;
  asm volatile("rdtime %0" : "=r"(ret));
  return ret / 10;
}

static void delay(unsigned long ms) {
  uint64_t prev_clock = user_clock();
  while (user_clock() - prev_clock < ms * 1000)
    ;
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
char space[0x2000] __attribute__((align(0x1000)));
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
char space[0x2000] __attribute__((align(0x1000)));

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
long bigarr[LARGE] __attribute__((align(0x1000))) = {};

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

#endif
