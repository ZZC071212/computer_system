#include "private_kdefs.h"

    .section .text.init
    .globl _start
_start:
    # 0. 设置 sp 为 _sbss, 并进行 mm_init
    la sp, _sbss
    call mm_init
    # 1. 将 stvec 设置为 _traps
    la t0, _traps
    csrw stvec, t0
    # 2. 设置 sie[STIE]
    li t0, 1<<5 // 2^5
    csrs sie, t0
    # 3. 设置第一次时钟中断的时间
    li a7, 0x54494d45
    li a6, 0
    li a1, 0
    li a2, 0
    li a3, 0
    li a4, 0
    li a5, 0
    # rdtime a0
    li a0, TIMECLOCK
    # li t0, TIMECLOCK
    # add a0, a0, t0
    ecall
    # 4. 设置 sstatus[SIE]
    li t0, 2 // SIE at bit 1
    csrs sstatus, t0
    # 5. 跳转到 start_kernel
    call start_kernel
    
    # 在 bss 段分配栈空间
    .section .bss.stack
    .space PGSIZE