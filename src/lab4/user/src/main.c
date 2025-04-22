#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <unistd.h>

// TODO for you:
// try to implement the C library function clock() so that it can be
// used across the kernel and user space, be DRY :)
static uint64_t user_clock(void) {
  uint64_t ret;
  asm volatile("rdtime %0" : "=r"(ret));
  return ret / 10;
}

// IMPORTANT: DO NOT move global variables into main function
int i;
uint64_t prev_clock;

int main(void) {
  register const void *const sp asm("sp");

  // lets just wait some time
  prev_clock = user_clock();
  while (user_clock() - prev_clock < 500000)
    ;

  while (1) {
    printf("\x1b[44m[U]\x1b[0m [PID = %d, sp = %p] i = %d @ %" PRIu64 "\n", getpid(), sp, ++i, prev_clock);

    // another interesting question for you to think about:
    // why when the tasks are scheduled the second time,
    // all tasks just suddenly "lined up" with the timer interrupt?
    prev_clock = user_clock();
    while (user_clock() - prev_clock < 1000000)
      ;
  }
}
