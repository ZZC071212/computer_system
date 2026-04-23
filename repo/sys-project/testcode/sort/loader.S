    .extern main
    .section .text.init
    .globl _start
_start:
    la sp, boot_stack_top
    li t0, 0x5000000
    li t1, 1
    # sb t1, 0(t0) # enable icache
    # sb t1, 8(t0) # enable dcache
    nop
    nop
    jal ra, main

    .section .bss.stack
    .globl boot_stack
boot_stack:
    .space 4096
    .globl boot_stack_top
boot_stack_top: