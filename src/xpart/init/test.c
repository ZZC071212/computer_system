#include "printk.h"
#include "defs.h"

// Please do not modify

void test() {
    unsigned long record_time = 0; 
    while (1) {
        // unsigned long present_time;
        // __asm__ volatile("rdtime %[t]" : [t] "=r" (present_time) : : "memory");
        // present_time /= 10000000;
        // if (record_time < present_time) {
        //     // printk("[DEBUG] kernel is running! Time: %lus\n", present_time);
        //     record_time = present_time; 
        // }
        // asm volatile("ecall");
        do_timer();
    }
}
