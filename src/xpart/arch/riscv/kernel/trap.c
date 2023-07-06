#include "printk.h"
#include "clock.h"
#include "proc.h"

extern struct task_struct* current;        
extern struct task_struct* task[NR_TASKS];

void trap_handler(unsigned long scause, unsigned long sepc) {
    if(scause & 0x8000000000000000 != 0) { //interrupt
        if(scause == 0x8000000000000005) { //timer interrupt
            // do_timer();
            // clock_set_next_event();
            #ifdef DEBUG
                printk("[DEBUG] Supervisor Mode Timer Interrupt\n");
            #endif

        }
    } else { //exception
        #ifdef DEBUG
            printk("[DEBUG]: Exception, scause: %lx, sepc: %lx \n", scause, sepc);
        #endif
    }
}