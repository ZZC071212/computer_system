#include "private_kdefs.h"


    .section .text.entry
    .align 4
    .globl _traps
_traps:
    # 1. 将寄存器和 sepc 保存到栈上
    addi sp, sp, -256
    sd x0, 0(sp)
    sd x1, 8(sp)
    # sd x2, 16(sp) // no sp
    sd x3, 24(sp)
    sd x4, 32(sp)
    sd x5, 40(sp)
    sd x6, 48(sp)
    sd x7, 56(sp)
    sd x8, 64(sp)
    sd x9, 72(sp)
    sd x10, 80(sp)
    sd x11, 88(sp)
    sd x12, 96(sp)
    sd x13, 104(sp)
    sd x14, 112(sp)
    sd x15, 120(sp)
    sd x16, 128(sp)
    sd x17, 136(sp)
    sd x18, 144(sp)
    sd x19, 152(sp)
    sd x20, 160(sp)
    sd x21, 168(sp)
    sd x22, 176(sp)
    sd x23, 184(sp)
    sd x24, 192(sp)
    sd x25, 200(sp)
    sd x26, 208(sp)
    sd x27, 216(sp)
    sd x28, 224(sp)
    sd x29, 232(sp)
    sd x30, 240(sp)
    sd x31, 248(sp)

    csrr a0, scause
    csrr a1, sepc
    sd a1, 16(sp)
    # 2. 调用 trap_handler
    #  a0 = scause, a1 = sepc
    call trap_handler
    # 3. 恢复寄存器和 sepc
    #    特别注意 sp 寄存器的恢复
    ld t0, 16(sp)
    csrw sepc, t0

    ld x0, 0(sp)
    ld x1, 8(sp)
    # ld x2, 16(sp) // no sp
    ld x3, 24(sp)
    ld x4, 32(sp)
    ld x5, 40(sp)
    ld x6, 48(sp)
    ld x7, 56(sp)
    ld x8, 64(sp)
    ld x9, 72(sp)
    ld x10, 80(sp)
    ld x11, 88(sp)
    ld x12, 96(sp)
    ld x13, 104(sp)
    ld x14, 112(sp)
    ld x15, 120(sp)
    ld x16, 128(sp)
    ld x17, 136(sp)
    ld x18, 144(sp)
    ld x19, 152(sp)
    ld x20, 160(sp)
    ld x21, 168(sp)
    ld x22, 176(sp)
    ld x23, 184(sp)
    ld x24, 192(sp)
    ld x25, 200(sp)
    ld x26, 208(sp)
    ld x27, 216(sp)
    ld x28, 224(sp)
    ld x29, 232(sp)
    ld x30, 240(sp)
    ld x31, 248(sp)

    addi sp, sp, 256
    # 4. 返回
    sret


    .globl __dummy
__dummy:
    la t0, dummy_task
    csrw sepc, t0
    sret
        
    .globl __switch_to
__switch_to:
    # 1. 将当前线程的上下文保存到当前线程的 thread_struct 中
    # a0: prev
    addi a0, a0, OFFSET_THREAD
    sd ra, 0(a0)
    sd sp, 8(a0)
    addi a0, a0, 16
    sd s0, 0(a0)
    sd s1, 8(a0)
    sd s2, 16(a0)
    sd s3, 24(a0)
    sd s4, 32(a0)
    sd s5, 40(a0)
    sd s6, 48(a0)
    sd s7, 56(a0)
    sd s8, 64(a0)
    sd s9, 72(a0)
    sd s10, 80(a0)
    sd s11, 88(a0)
    # 2. 从下一个线程的 thread_struct 中恢复上下文
    # a1: next
    addi a1, a1, OFFSET_THREAD
    ld ra, 0(a1)
    ld sp, 8(a1)
    addi a1, a1, 16
    ld s0, 0(a1)
    ld s1, 8(a1)
    ld s2, 16(a1)
    ld s3, 24(a1)
    ld s4, 32(a1)
    ld s5, 40(a1)
    ld s6, 48(a1)
    ld s7, 56(a1)
    ld s8, 64(a1)
    ld s9, 72(a1)
    ld s10, 80(a1)
    ld s11, 88(a1)

    ret