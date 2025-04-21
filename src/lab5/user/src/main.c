#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <unistd.h>

// define some tests
#define PFH1 11
#define PFH2 12
#define FORK1 21
#define FORK2 22
#define FORK3 23
#define FORK4 24

#ifndef USER_MAIN
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

char space[0x1000];
int var = 0;

int main(void) {
  while (1) {
    printf("\x1b[44m[U]\x1b[0m [PID = %d] var = %d\n", getpid(), var++);
    delay(DELAY_TIME);
  }
}

#elif USER_MAIN == FORK1

int var = 0;

int main(void) {
  pid_t pid = fork();
  const char *ident = pid ? "PARN" : "CHLD";

  while (1) {
    printf("\x1b[44m[U-%s]\x1b[0m [PID = %d] var = %d\n", ident, getpid(), var++);
    delay(DELAY_TIME + rand() % 1000);
  }
}

#elif USER_MAIN == FORK2

int var = 0;
char space[0x2000];

int main(void) {
  for (int i = 0; i < 3; i++) {
    printf("\x1b[44m[U]\x1b[0m [PID = %d] var = %d\n", getpid(), var++);
  }

  space[0x1000] = 'S';
  space[0x1001] = 'y';
  space[0x1002] = 's';
  space[0x1003] = '3';
  space[0x1004] = '-';
  space[0x1005] = 'L';
  space[0x1006] = 'a';
  space[0x1007] = 'b';
  space[0x1008] = '5';
  space[0x1009] = 0;

  pid_t pid = fork();
  const char *ident = pid ? "PARN" : "CHLD";

  printf("\x1b[44m[U-%s]\x1b[0m [PID = %d] Message: %s\n", ident, getpid(), &space[0x1000]);
  while (1) {
    printf("\x1b[44m[U-%s]\x1b[0m [PID = %d] var = %d\n", ident, getpid(), var++);
    delay(DELAY_TIME + rand() % 1000);
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
    delay(DELAY_TIME + rand() % 1000);
  }
}

#elif USER_MAIN == FORK4

#define LARGE 1000

int var = 0;
long bigarr[LARGE] = {};

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
    bigarr[i] = i;
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
      delay(DELAY_TIME + rand() % 1000);
    }
  }
}

#endif
