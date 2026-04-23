    .section .text
    .globl _sbi_start
_sbi_start:
    la sp, 1f
    addi sp, sp, -16
    li t0, 0xab
    sb t0, 0(sp)
    ld t1, 0(sp)
    li t0, 0xcd
    sb t0, 1(sp)
    ld t1, 0(sp)
    li t0, 0x1234
    sh t0, 2(sp)
    ld t1, 0(sp)
    li t0, 0x567890ef
    sw t0, 4(sp)
    ld t1, 0(sp)
    li t0, 0x1234567890abcdef
    sd t0, 8(sp)
    ld t1, 0(sp)

    // set MPP as S mode
    li t0, 0x800
    csrw mstatus, t0
    // set M trap address
    la t0, _sbi_trap_entry
    csrw mtvec, t0
    // set payload address of kernel
    la t0, _payload_address
    csrw mepc, t0
    // enable software interrupt
    li t0, 0x8
    csrw mie, t0
    // set stack top of M-mode sbi
    la t0, 1f
    csrw mscratch, t0
    // jump to kernel and switch to S mode
    li t0, 0x222
    csrw mideleg, t0
    li t0, 0xb109
    csrw medeleg, t0
    mret

    .section .bss
    .space 0x1000
1:

# .section .payload
# _payload_address:
#     .incbin FW_PAYLOAD_PATH
