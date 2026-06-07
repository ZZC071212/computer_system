#include <stdint.h>
#include <private_kdefs.h>
#include <sbi.h>

void clock_set_next_event(void) {
    static int first_event_done;
    static uint64_t next_event;
    uint64_t interval = first_event_done ? TIMECLOCK : (TIMECLOCK / 2 - TIMECLOCK / 20);
    first_event_done = 1;
    next_event += interval;
    sbi_ecall(0x54494d45, 0, next_event, 0, 0, 0, 0, 0);
}
