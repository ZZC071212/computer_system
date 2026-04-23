    .section .text.init
    .globl _start
_start:
    la sp, self_destruct
    csrw stvec, sp
    la sp, 1f
    slli t0, a0, 18
    sub sp, sp, t0
    bnez a1, 2f
    tail mt_test
2:
    call clear_bss
    tail main

clear_bss:
    la t0, _sbss
    la t1, _ebss
    addi t1, t1, 7
    andi t1, t1, -8
4:
    bgeu t0, t1, 3f
    sd zero, 0(t0)
    addi t0, t0, 8
    j 4b
3:
    ret

    .section .bss.stack
    .space 0x400000
1:
