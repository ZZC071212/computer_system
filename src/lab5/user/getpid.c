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

__attribute__((unused))
static inline long fork()
{
  long ret;
  asm volatile ("li a7, %1\n"
                "ecall\n"
                "mv %0, a0\n"
                : "+r" (ret) : "i" (220));
  return ret;
}

void wait(unsigned int n) {
    for (unsigned int i = 0; i < n; i++);
}

/*
 * Test your `Page Fault Handler` using the following `main`s
 */
/* PFH main #1 */
int main() {
    register unsigned long current_sp __asm__("sp");
    while (1) {
        printf("[U-MODE] pid: %ld, sp is %lx\n", getpid(), current_sp);
        wait(WAIT_TIME);
    }

    return 0;
}

/* PFH main #2 */
// char global_placeholder[0x1000];
// unsigned long global_increment = 0;

// int main() {
//     while (1) {
//         printf("[U-MODE] pid: %ld, increment: %ld\n", getpid(), global_increment++);
//         wait(WAIT_TIME);
//     }
// }


/*
 * Test your `fork` using the following `main`s
 */
/* Fork main #1 */
// int global_variable = 0;

// int main() {
//     int pid;

//     pid = fork();

//     if (pid == 0) {
//         while (1) {
//             printf("[U-CHILD] pid: %ld is running! global_variable: %d\n", getpid(), global_variable++);
//             wait(WAIT_TIME);
//         } 
//     } else {
//         while (1) {
//             printf("[U-PARENT] pid: %ld is running! global_variable: %d\n", getpid(), global_variable++);
//             wait(WAIT_TIME);
//         } 
//     }
//     return 0;
// }

/* Fork main #2 */
// int global_variable = 0;
// char placeholder[8192];

// int main() {
//     int pid;

//     for (int i = 0; i < 3; i++) {
//         printf("[U] pid: %ld is running! global_variable: %d\n", getpid(), global_variable++);
//     }

//     placeholder[4096] = 'S';
//     placeholder[4097] = 'y';
//     placeholder[4098] = 's';
//     placeholder[4099] = '3';
//     placeholder[4100] = '-';
//     placeholder[4101] = 'L';
//     placeholder[4102] = 'a';
//     placeholder[4103] = 'b';
//     placeholder[4104] = '5';
//     placeholder[4105] = '\0';

//     pid = fork();

//     if (pid == 0) {
//         printf("[U-CHILD] pid: %ld is running! Message: %s\n", getpid(), &placeholder[4096]);
//         while (1) {
//             printf("[U-CHILD] pid: %ld is running! global_variable: %d\n", getpid(), global_variable++);
//             wait(WAIT_TIME);
//         } 
//     } else {
//         printf("[U-PARENT] pid: %ld is running! Message: %s\n", getpid(), &placeholder[4096]);
//         while (1) {
//             printf("[U-PARENT] pid: %ld is running! global_variable: %d\n", getpid(), global_variable++);
//             wait(WAIT_TIME);
//         } 
//     }
//     return 0;
// }

/* Fork main #3 */
// int global_variable = 0;

// int main() {

//     printf("[U] pid: %ld is running! global_variable: %d\n", getpid(), global_variable++);
//     fork();
//     fork(); // multiple references to one page

//     printf("[U] pid: %ld is running! global_variable: %d\n", getpid(), global_variable++);
//     fork();

//     while(1) {
//         printf("[U] pid: %ld is running! global_variable: %d\n", getpid(), global_variable++);
//         wait(WAIT_TIME);
//     }
// }

/* Fork main #4 */
// #define LARGE 1000

// int global_variable = 0;
// unsigned long something_large_here[LARGE] = {0};

// int fib(int times) {
//     if (times <= 2) {
//         return 1;
//     } else {
//         return fib(times - 1) + fib(times - 2);
//     }
// }

// int main() {
//     for (int i = 0; i < LARGE; i++) {
//         something_large_here[i] = i;
//     }

//     int pid = fork();
//     printf("[U] fork returns %d\n", pid);

//     if (pid == 0) {
//         while(1) {
//         printf("[U-CHILD] pid: %ld is running! the %dth fibonacci number is %d and the number @ %d in the large array is %d\n", getpid(), global_variable, fib(global_variable), LARGE-1-global_variable, something_large_here[LARGE-1-global_variable]);
//         global_variable++;
//         wait(0xFFFFFF);
//         }
//     } else {
//         while (1) {
//             printf("[U-PARENT] pid: %ld is running! the %dth fibonacci number is %d and the number @ %d in the large array is %d\n", getpid(), global_variable, fib(global_variable), LARGE-1-global_variable, something_large_here[LARGE-1 - global_variable]);
//             global_variable++;
//             wait(0xFFFFFF);
//         }
//     }
// }
