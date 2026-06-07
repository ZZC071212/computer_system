#include "private_kdefs.h"

    .section .text.entry
    .align 4
    .globl _traps
    .globl __dummy
    .globl __switch_to
    .globl ret_from_fork

__dummy:
    csrrw sp, sscratch, sp #交换 sp 和 sscratch
    sret

_traps:
    csrrw sp, sscratch, sp
    addi sp, sp, -PT_SIZE
    #在内核栈上开辟一块struct pt_regs 大小的空间，用来保存用户寄存器

    #保存所有通用寄存器到内核栈pt_regs结构体中
    sd zero, PT_X0(sp)
    sd ra,   PT_RA(sp)
    sd t0,   PT_T0(sp)
    csrr t0, sscratch
    sd t0,   PT_SP(sp)
    sd gp,   PT_GP(sp)
    sd tp,   PT_TP(sp)
    sd t1,   PT_T1(sp)
    sd t2,   PT_T2(sp)
    sd s0,   PT_S0(sp)
    sd s1,   PT_S1(sp)
    sd a0,   PT_A0(sp)
    sd a1,   PT_A1(sp)
    sd a2,   PT_A2(sp)
    sd a3,   PT_A3(sp)
    sd a4,   PT_A4(sp)
    sd a5,   PT_A5(sp)
    sd a6,   PT_A6(sp)
    sd a7,   PT_A7(sp)
    sd s2,   PT_S2(sp)
    sd s3,   PT_S3(sp)
    sd s4,   PT_S4(sp)
    sd s5,   PT_S5(sp)
    sd s6,   PT_S6(sp)
    sd s7,   PT_S7(sp)
    sd s8,   PT_S8(sp)
    sd s9,   PT_S9(sp)
    sd s10,  PT_S10(sp)
    sd s11,  PT_S11(sp)
    sd t3,   PT_T3(sp)
    sd t4,   PT_T4(sp)
    sd t5,   PT_T5(sp)
    sd t6,   PT_T6(sp)

    #保存 trap 返回地址
    csrr t0, sepc
    sd t0, PT_SEPC(sp)

    #传参数，调用函数
    mv a0, sp
    csrr a1, scause
    csrr a2, stval
    call trap_handler

ret_from_fork:
    ld t0, PT_SEPC(sp)
    csrw sepc, t0
    ld t0, PT_SP(sp)
    csrw sscratch, t0

    #恢复通用寄存器
    ld ra,   PT_RA(sp)
    ld gp,   PT_GP(sp)
    ld tp,   PT_TP(sp)
    ld t0,   PT_T0(sp)
    ld t1,   PT_T1(sp)
    ld t2,   PT_T2(sp)
    ld s0,   PT_S0(sp)
    ld s1,   PT_S1(sp)
    ld a0,   PT_A0(sp)
    ld a1,   PT_A1(sp)
    ld a2,   PT_A2(sp)
    ld a3,   PT_A3(sp)
    ld a4,   PT_A4(sp)
    ld a5,   PT_A5(sp)
    ld a6,   PT_A6(sp)
    ld a7,   PT_A7(sp)
    ld s2,   PT_S2(sp)
    ld s3,   PT_S3(sp)
    ld s4,   PT_S4(sp)
    ld s5,   PT_S5(sp)
    ld s6,   PT_S6(sp)
    ld s7,   PT_S7(sp)
    ld s8,   PT_S8(sp)
    ld s9,   PT_S9(sp)
    ld s10,  PT_S10(sp)
    ld s11,  PT_S11(sp)
    ld t3,   PT_T3(sp)
    ld t4,   PT_T4(sp)
    ld t5,   PT_T5(sp)
    ld t6,   PT_T6(sp)

    addi sp, sp, PT_SIZE#释放内核栈上的 pt_regs 空间。
    csrrw sp, sscratch, sp
    sret

__switch_to:
    sd ra, TASK_THREAD_RA(a0)
    sd sp, TASK_THREAD_SP(a0)
    sd s0, TASK_THREAD_S0(a0)
    sd s1, TASK_THREAD_S1(a0)
    sd s2, TASK_THREAD_S2(a0)
    sd s3, TASK_THREAD_S3(a0)
    sd s4, TASK_THREAD_S4(a0)
    sd s5, TASK_THREAD_S5(a0)
    sd s6, TASK_THREAD_S6(a0)
    sd s7, TASK_THREAD_S7(a0)
    sd s8, TASK_THREAD_S8(a0)
    sd s9, TASK_THREAD_S9(a0)
    sd s10, TASK_THREAD_S10(a0)
    sd s11, TASK_THREAD_S11(a0)

    csrr t0, sepc
    sd t0, TASK_THREAD_SEPC(a0)
    csrr t0, sstatus
    sd t0, TASK_THREAD_SSTATUS(a0)
    csrr t0, sscratch
    sd t0, TASK_THREAD_SSCRATCH(a0)
    csrr t0, stval
    sd t0, TASK_THREAD_STVAL(a0)
    csrr t0, scause
    sd t0, TASK_THREAD_SCAUSE(a0)

    ld t0, TASK_PGD(a1)
    #切换页表
    li t1, PA2VA_OFFSET
    sub t0, t0, t1
    #虚拟地址转物理地址
    srli t0, t0, 12
    #页表根地址右移 12 位，得到 PPN
    li t1, 8
    slli t1, t1, 60
    #构造 satp.MODE = 8，即 Sv39
    or t0, t0, t1
    csrw satp, t0
    # 组合出新的 satp 并写入，完成页表切换
    sfence.vma zero, zero
    #刷新 TLB

    ld t0, TASK_THREAD_SEPC(a1)
    csrw sepc, t0
    ld t0, TASK_THREAD_SSTATUS(a1)
    csrw sstatus, t0
    ld t0, TASK_THREAD_SSCRATCH(a1)
    csrw sscratch, t0

    ld ra, TASK_THREAD_RA(a1)
    ld sp, TASK_THREAD_SP(a1)
    ld s0, TASK_THREAD_S0(a1)
    ld s1, TASK_THREAD_S1(a1)
    ld s2, TASK_THREAD_S2(a1)
    ld s3, TASK_THREAD_S3(a1)
    ld s4, TASK_THREAD_S4(a1)
    ld s5, TASK_THREAD_S5(a1)
    ld s6, TASK_THREAD_S6(a1)
    ld s7, TASK_THREAD_S7(a1)
    ld s8, TASK_THREAD_S8(a1)
    ld s9, TASK_THREAD_S9(a1)
    ld s10, TASK_THREAD_S10(a1)
    ld s11, TASK_THREAD_S11(a1)

    ret
