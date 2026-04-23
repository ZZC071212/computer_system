#include "../test_macros.h"
.section .text
.global _start
_start:
test1:
    addi x1, x0, 1
    addi x2, x0, 1
    addi x4, x0, 5
fibonacci:
    RACE_PADDING
    RACE_PADDING
    add x3, x1, x2
    RACE_PADDING
    RACE_PADDING
    RACE_PADDING
    add x1, x2, x3
    RACE_PADDING
    RACE_PADDING
    RACE_PADDING
    add x2, x1, x3
    addi x4, x4, -1
    RACE_PADDING
    RACE_PADDING
    RACE_PADDING
    bne x0, x4, fibonacci
    RACE_PADDING
    RACE_PADDING
    addi x5, x0, 0x63D
    RACE_PADDING
    RACE_PADDING
    RACE_PADDING
    bne x2, x5, fail
    RACE_PADDING
    RACE_PADDING

test2:
    lui x2, %hi(databegin)
    RACE_PADDING
    RACE_PADDING
    RACE_PADDING
    addi x2, x2, %lo(databegin)
    lui x3, %hi(dataend)
    RACE_PADDING
    RACE_PADDING
    RACE_PADDING
    addi x3, x3, %lo(dataend)
    lb x1,0(x2)
    RACE_PADDING
    RACE_PADDING
    FORW_PADDING
    RACE_PADDING
    FORW_PADDING
    sb x1,0(x3)
    lb x1,1(x2)
    RACE_PADDING
    RACE_PADDING
    FORW_PADDING
    RACE_PADDING
    FORW_PADDING
    sb x1,1(x3)
    lh x1,2(x2)
    RACE_PADDING
    RACE_PADDING
    FORW_PADDING
    RACE_PADDING
    FORW_PADDING
    sh x1,2(x3)
    lw x1,4(x2)
    RACE_PADDING
    RACE_PADDING
    FORW_PADDING
    RACE_PADDING
    FORW_PADDING
    sw x1,4(x3)
    ld x1,8(x2)
    RACE_PADDING
    RACE_PADDING
    FORW_PADDING
    RACE_PADDING
    FORW_PADDING
    sd x1,8(x3)
    lbu x1,0(x2)
    RACE_PADDING
    RACE_PADDING
    FORW_PADDING
    RACE_PADDING
    FORW_PADDING
    sd x1,16(x3)
    lb x1,0(x2)
    RACE_PADDING
    RACE_PADDING
    FORW_PADDING
    RACE_PADDING
    FORW_PADDING
    sd x1,24(x3)
    lhu x1,0(x2)
    RACE_PADDING
    RACE_PADDING
    FORW_PADDING
    RACE_PADDING
    FORW_PADDING
    sd x1,32(x3)
    lh x1,0(x2)
    RACE_PADDING
    RACE_PADDING
    FORW_PADDING
    RACE_PADDING
    FORW_PADDING
    sd x1,40(x3)
    lwu x1,0(x2)
    RACE_PADDING
    RACE_PADDING
    FORW_PADDING
    RACE_PADDING
    FORW_PADDING
    sd x1,48(x3)
    lw x1,0(x2)
    RACE_PADDING
    RACE_PADDING
    FORW_PADDING
    RACE_PADDING
    FORW_PADDING
    sd x1,56(x3)

    addi x1, x0, 8
    addi x5, x0, 8
memcmp:
    RACE_PADDING
    FORW_PADDING
    RACE_PADDING
    FORW_PADDING
    beq x1, x0, test3
    ld x4, 0(x2)
    ld x6, 0(x3)
    add x2, x2, x5
    add x3, x3, x5
    addi x1, x1, -1
    bne x4, x6, fail
    RACE_PADDING
    FORW_PADDING
    RACE_PADDING
    FORW_PADDING
    j memcmp
    RACE_PADDING
    FORW_PADDING
    RACE_PADDING
    FORW_PADDING

test3:
    lui x1, 0xDEADB     # 0xFFFFFFFFDEADB000
    ori x2, x0, 0xEF    # 0x00000000000000EF
    RACE_PADDING
    RACE_PADDING
    RACE_PADDING
    add x3, x1, x2      # 0xFFFFFFFFDEADB0EF
    addi x8,x8,1        # 0x0000000000000001
    RACE_PADDING
    RACE_PADDING
    RACE_PADDING
    slli x8,x8,32       # 0x0000000100000000
    RACE_PADDING
    RACE_PADDING
    RACE_PADDING
    add x3,x3,x8        # 0x00000000DEADB0EF
    sub x1, x2, x1      # 0x00000000215250EF
    addi x2, x0, 1      # 0x0000000000000001
    RACE_PADDING
    RACE_PADDING
    RACE_PADDING
    srl x4, x3, x2      # 0x6F56D877
    RACE_PADDING
    RACE_PADDING
    RACE_PADDING
    and x2, x1, x4      # 0x21525067
    lui x1, 0x21525     # 0x21525000
    RACE_PADDING
    RACE_PADDING
    RACE_PADDING
    addi x1, x1, 0x67   # 0x21525067
    RACE_PADDING
    RACE_PADDING
    RACE_PADDING
    bne x2, x1, fail
    RACE_PADDING
    RACE_PADDING
    RACE_PADDING
    lui x1, %hi(jalr_here)
    RACE_PADDING
    RACE_PADDING
    RACE_PADDING
    addi x1, x1, %lo(jalr_here)
    RACE_PADDING
    RACE_PADDING
    RACE_PADDING
    jalr x1, x1, 0
jalr_here:
    RACE_PADDING
    FORW_PADDING
    RACE_PADDING
    FORW_PADDING
    lui x2, %hi(jalr_here)
    RACE_PADDING
    RACE_PADDING
    RACE_PADDING
    addi x2, x2, %lo(jalr_here)
    RACE_PADDING
    RACE_PADDING
    RACE_PADDING
    bne x1, x2, fail
    RACE_PADDING
    RACE_PADDING
TEST_PASSFAIL

.section .data

databegin:
.word 0xF234F6F8
.word 0x87654321
.word 0x23333333
.word 0x66666666
.dword 0x00000000000000F8
.dword 0xFFFFFFFFFFFFFFF8
.dword 0x000000000000F6F8
.dword 0xFFFFFFFFFFFFF6F8
.dword 0x00000000F234F6F8
.dword 0xFFFFFFFFF234F6F8
dataend:
.space 0x40

