#include "syscall.h"
#include "stdio.h"

#define WAIT_TIME 0x1FFFFFFF

static inline long getpid() {
    long ret;
    asm volatile ("li a7, %1\n"
                  "ecall\n"
                  "mv %0, a0\n"
                : "+r" (ret) 
                : "i" (SYS_GETPID));
    return ret;
}

void wait(unsigned int n) {
    for (unsigned int i = 0; i < n; i++);
}

int main() {
    register unsigned long current_sp __asm__("sp");
    while (1) {
        printf("[U-MODE] pid: %ld, sp is %lx\n", getpid(), current_sp);
        wait(WAIT_TIME);
    }

    return 0;
}

/* THINK 🤔️ */
// char global_placeholder[0x1000];
// unsigned long global_increment = 0;

// int main() {
//     while (1) {
//         printf("[U-MODE] pid: %ld, increment: %ld\n", getpid(), global_increment++);
//         wait(WAIT_TIME);
//     }
// }