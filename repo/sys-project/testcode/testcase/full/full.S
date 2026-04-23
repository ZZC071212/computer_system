#include "../test_macros.h"

.section .text
.globl _start

_start:

TEST_RR_OP( 1,  add, 0x0000000a, 0x00000003, 0x00000007 );
TEST_RR_SRC1_EQ_DEST( 2, sub, 2, 13, 11 );
TEST_RR_SRC2_EQ_DEST( 3, sll, 0x00004000, 0x00000001, 14 );
TEST_RR_SRC2_EQ_DEST( 4, slt, 1, 11, 13 );
TEST_RR_ZERODEST( 5, sltu, 16, 30 );
TEST_RR_OP( 6, xor, 0xff, 0x0f, 0xf0 );
#define TEST_SRL(n, v, a) \
  TEST_RR_OP(n, srl, ((v) & ((1 << (64-1) << 1) - 1)) >> (a), v, a)
TEST_RR_ZEROSRC2( 7, srl, 32, 32 );
TEST_RR_ZEROSRC1( 8, sra, 0, 15 );
TEST_RR_SRC1_EQ_DEST( 9, or, 0x0f, 0x00, 0x0f );
TEST_RR_ZERODEST( 10, and, 0x11, 0x22 );

TEST_IMM_OP( 11,  addi, 0x0000000a, 0x00000003, 0x007 );
TEST_IMM_SRC1_EQ_DEST( 12, slti, 1, 11, 13 );
TEST_IMM_OP( 13,  sltiu, 1, 0x0000000000000003, 0x007 );
TEST_IMM_SRC1_EQ_DEST( 14, sltiu, 1, 11, 13 );
TEST_IMM_SRC1_EQ_DEST( 15, xori, 0x0f, 0x00, 0x0f );
TEST_IMM_OP( 16, ori, 0xff, 0xff, 0x0f );
TEST_IMM_OP( 17, andi, 0x00, 0x0f, 0xf0 );
TEST_IMM_OP( 18,  slli, 0x0000000000004000, 0x0000000000000001, 14 );
#define TEST_SRLI(n, v, a) \
  TEST_IMM_OP(n, srli, ((v) & ((1 << (64-1) << 1) - 1)) >> (a), v, a)
TEST_SRLI( 19,  0x20f, 14 );
TEST_IMM_OP( 20, srai, 0xc0, 0x181, 1  );
TEST_LD_OP( 21, ld, 0xDE, -24, tdat4LD );

TEST_BR2_OP_TAKEN( 22, beq,  1,  1 );
TEST_BR2_OP_NOTTAKEN( 23, beq, -1,  1 );
TEST_BR2_OP_TAKEN( 24, bne,  1, -1 );
TEST_BR2_OP_NOTTAKEN( 25, bne, -1, -1 );
TEST_BR2_OP_TAKEN( 26, blt, -2, -1 );
TEST_BR2_OP_NOTTAKEN( 27, blt,  1, -2 );
TEST_BR2_OP_TAKEN( 28, bge,  1,  0 );
TEST_BR2_OP_NOTTAKEN(  29, bge, -1,  1 );
TEST_BR2_OP_TAKEN( 30, bgeu, 0x00000001, 0x00000000 );
TEST_BR2_OP_NOTTAKEN(  31, bgeu, -2, -1 );
TEST_BR2_OP_TAKEN( 32, bltu, 0x00000000, -1 );
TEST_BR2_OP_NOTTAKEN( 33, bltu, -1, 0x00000000 );

TEST_ST_OP( 34, ld, sd, 0xAB, 8,  tdatSD );
TEST_ST_OP( 35, ld, sd, 0x78, -8,  tdat2SD );

TEST_CASE( 36, x1, 0xfffffffffffff800, lui x1, 0x80000;sra x1,x1,20);
TEST_CASE(37, a0, -1000, \
  .align 3; \
  lla a0, 1f - 1000; \
  jal a1, 1f; \
  1: sub a0, a0, a1; \
)
test_38:
  li  TESTNUM, 38
  li  ra, 0
  jal x4, target_38

linkaddr_38:
  nop
  nop
  j fail

target_38:
  la  x2, linkaddr_38
  bne x2, x4, fail

TEST_LD_OP( 39, lb, 0xfffffffffffffff0, 2,  tdatLB );
TEST_LD_OP( 40, lh, 0xffffffffffffff00, 2,  tdatLH );
TEST_LD_OP( 41, lw, 0x000000000ff00ff0, 8,  tdatLW );
TEST_LD_OP( 42, lbu, 0x000000000000000f, 3, tdatLB );
TEST_LD_OP( 43, lhu, 0x000000000000f00f, 6, tdatLH );
TEST_LD_OP( 44, lwu, 0x0000000000ff00ff, -12, tdat4LW );
TEST_ST_OP( 45, lb, sb, 0xffffffffffffffa0, 2, tdatLB );
TEST_ST_OP( 46, lh, sh, 0xffffffffffffa00a, -6,  tdat4LH );
TEST_ST_OP( 47, lw, sw, 0xffffffffa00aa00a, -12,   tdat4LW );
TEST_IMM_OP( 48, slliw, 0xffffffff80000000, 0xffffffffffffffff, 31 );
TEST_IMM_OP( 49, srliw, 0x0000000010909090, 0x0000000021212121, 1  );
TEST_IMM_OP( 50, sraiw, 0xfffffffffffe0606, 0xffffffff81818181, 14 );
TEST_RR_OP( 51, addw, 0xffffffff80007ffe, 0x000000007fffffff, 0x0000000000007fff );
TEST_RR_OP( 52,  subw, 0xffffffff80000000, 0xffffffff80000000, 0x0000000000000000 );
TEST_RR_OP( 53, sllw, 0x0000000048484000, 0x0000000021212121, 0xffffffffffffffee );
TEST_RR_OP( 54, srlw, 0x0000000010909090, 0x0000000021212121, 0xffffffffffffffe1 );
TEST_RR_OP( 55, sraw, 0xffffffffff030303, 0xffffffff81818181, 0xffffffffffffffe7 );
test_56:
  li  TESTNUM, 56
  la  t0, target_56
  jalr t0, t0, 0
linkaddr_56:
  j fail
target_56:
  la  t1, linkaddr_56
  bne t0, t1, fail

TEST_RR_OP( 57, add, 0xffffffff80007fff, 0xffffffff80000000, 0x0000000000007fff );
TEST_IMM_OP( 58, addi, 0xffffffff800007ff, 0xffffffff80000000, 0x7ff );
TEST_IMM_OP( 59,  addiw, 0x000000007ffff800, 0xffffffff80000000, 0x800 );
TEST_RR_OP( 60,  addw, 0x000000007fffffff, 0x000000007fffffff, 0x0000000000000000 );
TEST_RR_OP( 61, and, 0xf000f000, 0xf00ff00f, 0xf0f0f0f0 );
TEST_IMM_OP( 62, andi, 0x00000000, 0xf00ff00f, 0x0f0 );
TEST_CASE(63, a0, -10000, \
  .align 3; \
  lla a0, 1f - 10000; \
  jal a1, 1f; \
  1: sub a0, a0, a1; \
)
TEST_IMM_DEST_BYPASS( 64,  2, xori, 0xfffffffff00ff0ff, 0xfffffffff00ff00f, 0x0f0 );
TEST_RR_OP( 65, xor, 0x00ff00ff, 0xf00ff00f, 0xf0f0f0f0 );
TEST_RR_OP( 66, subw, 0xffffffff80007fff, 0x000000007fffffff, 0xffffffffffff8000 );
TEST_RR_OP( 67, sub, 0x0000000080007fff, 0x000000007fffffff, 0xffffffffffff8000 );
TEST_RR_OP( 68, srlw, 0x0000000000424242, 0x0000000021212121, 0xffffffffffffffe7 );
TEST_RR_OP( 69, srlw, 0x0000000001234567, 0xffffffff12345678, 4 );
TEST_IMM_OP( 70, srliw, 0x0000000001234567, 0xffffffff12345678, 4 );
TEST_SRLI( 71, 0x0000000021212121, 31 );
TEST_RR_OP( 72, srl, 0x0000000010909090, 0x0000000021212121, 0xffffffffffffffc1 );
TEST_RR_OP( 73, sraw, 0xfffffffffffe0606, 0xffffffff81818181, 14 );
TEST_RR_OP( 74, sra, 0xffffffffc0c0c0c0, 0xffffffff81818181, 0xffffffffffffffc1 );
TEST_RR_OP( 75, sltu, 1, 0x7fffffff, 0xffff8000 );
TEST_IMM_OP( 76, ori, 0xfffffffff00ff0ff, 0xfffffffff00ff00f, 0x0f0 );
TEST_RR_OP( 77, sll, 0x0000000042424242, 0x0000000021212121, 0xffffffffffffffc1 );
TEST_IMM_OP( 78, slli, 0x0909080000000000, 0x0000000021212121, 43 );
TEST_IMM_OP( 79, slliw, 0xffffffff93456780, 0x0000000099345678, 4 );
TEST_RR_OP( 80, sllw, 0x0000000023456780, 0xffffffff12345678, 4 );

TEST_PASSFAIL

.section .data

tdatLD:
tdat1LD:  .dword 0xDE
tdat2LD:  .dword 0xAB
tdat3LD:  .dword 0xCD
tdat4LD:  .dword 0xFF

tdatSD:
tdat1SD:  .dword 0xdeadbeefdeadbeef
tdat2SD:  .dword 0xdeadbeefdeadbeef

tdatLB:
tdat1LB:  .byte 0xff
tdat2LB:  .byte 0x00
tdat3LB:  .byte 0xf0
tdat4LB:  .byte 0x0f

tdatLH:
tdat1LH:  .half 0x00ff
tdat2LH:  .half 0xff00
tdat3LH:  .half 0x0ff0
tdat4LH:  .half 0xf00f

tdatLW:
tdat1LW:  .word 0x00ff00ff
tdat2LW:  .word 0xff00ff00
tdat3LW:  .word 0x0ff00ff0
tdat4LW:  .word 0xf00ff00f