#ifndef _SBI_H
#define _SBI_H

#include "stdint.h"

struct sbiret {
    uint64_t error;
    uint64_t value;
};

struct sbiret sbi_ecall(uint64_t eid, uint64_t fid,
                        uint64_t arg0, uint64_t arg1, uint64_t arg2,
                        uint64_t arg3, uint64_t arg4, uint64_t arg5);


void sbi_set_timer(uint64_t stime_value);
// 写入CSR寄存器的宏
#define csr_write(reg, val) ({ \
    asm volatile("csrw " #reg ", %0" ::"r"(val)); \
})

// 读取CSR寄存器的宏
#define csr_read(reg) ({ \
    unsigned long __tmp; \
    asm volatile ("csrr %0, " #reg : "=r"(__tmp)); \
    __tmp; \
})

#endif //_SBI_H