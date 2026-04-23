    .section .text
    .globl _start1
_start1:
    li t0, 1
    li t1, 1
    li t2, 5
    li t4, 0x63d
fibonacci:
    add t3, t0, t1
    add t0, t1, t3
    add t1, t0, t3
    addi t2, t2, -1
    bnez t2, fibonacci
    bne t1, t4, fail1
test1:
    li t0, 0x3de
    li t1, -0x2ad
    csrw mscratch, t0
    csrrw t3, mscratch, t1
    csrrwi t2, mscratch, 0x1c
    bne t0, t3, fail1
    bne t1, t2, fail1
    li t4, 0x1c
    li t0, -0x1be              # A
    csrrw t3, mscratch, t1
    csrrw t2, mscratch, t0     # mscratch = A
    bne t4, t3, fail1
    bne t1, t2, fail1
    li t1, 0x3ef               # B
    csrrs t2, mscratch, t1     # mscratch = A | B, t2 = A
    csrrc t3, mscratch, t0     # mscratch = B & ~A, t3 = A | B
    csrrwi t6, mscratch, 5     # t6 = B & ~A
    or t4, t0, t1              # t4 = A | B
    not t5, t0                 # t5 = ~A
    and t5, t5, t1             # t5 = ~A & B
    bne t2, t0, fail1
    bne t3, t4, fail1
    bne t5, t6, fail1
    csrrsi t0, mscratch, 0x16   # t0 = 5, mscratch = 5 | 0x16 = 0x17
    csrrci t1, mscratch, 0x1d   # t1 = 0x17, mscratch = 0x17 & ~0x1d = 2
    csrr t2, mscratch           # t2 = 2
    li t3, 0x17
    li t4, 0x2
    bne t1, t3, fail1
    bne t2, t4, fail1

pass1:
    li t0, 0x80000000
    jr t0
fail1:
    unimp
    j fail1
