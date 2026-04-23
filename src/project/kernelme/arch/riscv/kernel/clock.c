#include <stdint.h>
#include <private_kdefs.h>
#include <sbi.h>

void clock_set_next_event(void) {
    sbi_ecall(0x54494d45, 0, TIMECLOCK, 0, 0, 0, 0, 0);
}