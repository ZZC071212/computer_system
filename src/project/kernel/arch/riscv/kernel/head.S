#include "private_kdefs.h"

    .section .text.init
    .globl _start
_start:
    # 0. 设置启动栈，并建立早期虚拟内存映射
    la sp, boot_stack_top
    call setup_vm
    call relocate

    # 1. 初始化内存管理，并切换到最终页表
    call mm_init
    call setup_vm_final

    # 2. 将 stvec 设置为 _traps
    la t0, _traps
    csrw stvec, t0
    # 3. 设置 sie[STIE]
    li t0, 1<<5 // 2^5
    csrs sie, t0
    # 4. 设置第一次时钟中断的时间
    call clock_set_next_event
    # 5. 设置 sstatus[SIE]
    li t0, 2 // SIE at bit 1
    csrs sstatus, t0
    # 6. 跳转到 start_kernel
    call start_kernel

relocate:
    # 1. set general purpose registers to appropriate values
    #    - set ra = ra + PA2VA_OFFSET
    #    - set sp = sp + PA2VA_OFFSET, if needed
    # satp 写入后 ret 应跳转到虚拟地址，栈也切换到 direct mapping 区域。
    li t0, PA2VA_OFFSET
    #返回地址加上偏移，跳转到虚拟地址
    add ra, ra, t0
    add sp, sp, t0

    # flush TLB
    #保证 setup_vm 写入的 PTE 生效。让硬件页表遍历按照刚才写的PTE来
    sfence.vma zero, zero

    # 2. set satp to use early_pgtbl
    #    - set satp to use Sv39 mode

    la t0, early_pgtbl #物理地址
    srli t0, t0, 12 #页表项的高位是物理页号，物理地址右移12位得到物理页号
    li t1, 8
    slli t1, t1, 60 #satp.MODE = 8 表示 Sv39
    or t0, t0, t1 #合并成最终的satp
    csrw satp, t0

    ret #此时ret还在低地址附近，所以做了等值映射，之后cpu还可以取到ret,真正跳到虚拟地址

    # 在 bss 段分配栈空间
    .section .bss.stack
    .globl boot_stack
boot_stack:
    .space PGSIZE
    .globl boot_stack_top
boot_stack_top:
