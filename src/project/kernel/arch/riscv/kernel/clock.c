#include <stdint.h>
#include <private_kdefs.h>
#include <sbi.h>

void clock_set_next_event(void) {
    uint64_t now;
    asm volatile("rdtime %0" : "=r"(now));
    sbi_ecall(0x54494d45, 0, now + TIMECLOCK, 0, 0, 0, 0, 0);
}
