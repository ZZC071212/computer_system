#include "../test_macros.h"

.section .text
.globl _start

_start:

TEST_CASE( 1, x5, 0x0000000000000000, \
  la  x1, tdatLB; \
  addi x1, x1, -6; \
  lb x5, 7(x1); \
)
TEST_LD_OP( 2, lb, 0xffffffffffffffff, 0,  tdatLB );
TEST_LD_OP( 3, lb, 0x0000000000000000, 1,  tdatLB );
TEST_LD_OP( 4, lb, 0xfffffffffffffff0, 2,  tdatLB );
TEST_LD_OP( 5, lb, 0x000000000000000f, 3, tdatLB );
TEST_LD_OP( 6, lb, 0xffffffffffffffff, -3, tdat4LB );
TEST_LD_OP( 7, lb, 0x0000000000000000, -2,  tdat4LB );
TEST_LD_OP( 8, lb, 0xfffffffffffffff0, -1,  tdat4LB );
TEST_LD_OP( 9, lb, 0x000000000000000f, 0,   tdat4LB );
TEST_CASE( 10, x5, 0xffffffffffffffff, \
  la  x1, tdatLB; \
  addi x1, x1, -32; \
  lb x5, 32(x1); \
)

TEST_CASE( 11, x5, 0xffffffffffffff00, \
  la  x1, tdatLH; \
  addi x1, x1, -5; \
  lh x5, 7(x1); \
)
TEST_LD_OP( 12, lh, 0x00000000000000ff, 0,  tdatLH );
TEST_LD_OP( 13, lh, 0xffffffffffffff00, 2,  tdatLH );
TEST_LD_OP( 14, lh, 0x0000000000000ff0, 4,  tdatLH );
TEST_LD_OP( 15, lh, 0xfffffffffffff00f, 6, tdatLH );
TEST_LD_OP( 16, lh, 0x00000000000000ff, -6,  tdat4LH );
TEST_LD_OP( 17, lh, 0xffffffffffffff00, -4,  tdat4LH );
TEST_LD_OP( 18, lh, 0x0000000000000ff0, -2,  tdat4LH );
TEST_LD_OP( 19, lh, 0xfffffffffffff00f,  0, tdat4LH );
TEST_CASE( 20, x5, 0x00000000000000ff, \
  la  x1, tdatLH; \
  addi x1, x1, -32; \
  lh x5, 32(x1); \
)

TEST_CASE( 21, x5, 0xffffffffff00ff00, \
  la  x1, tdatLW; \
  addi x1, x1, -3; \
  lw x5, 7(x1); \
)
TEST_LD_OP( 22, lw, 0x0000000000ff00ff, 0,  tdatLW );
TEST_LD_OP( 23, lw, 0xffffffffff00ff00, 4,  tdatLW );
TEST_LD_OP( 24, lw, 0x000000000ff00ff0, 8,  tdatLW );
TEST_LD_OP( 25, lw, 0xfffffffff00ff00f, 12, tdatLW );
TEST_LD_OP( 26, lw, 0x0000000000ff00ff, -12, tdat4LW );
TEST_LD_OP( 27, lw, 0xffffffffff00ff00, -8,  tdat4LW );
TEST_LD_OP( 28, lw, 0x000000000ff00ff0, -4,  tdat4LW );
TEST_LD_OP( 29, lw, 0xfffffffff00ff00f, 0,   tdat4LW );
TEST_CASE( 30, x5, 0x0000000000ff00ff, \
  la  x1, tdatLW; \
  addi x1, x1, -32; \
  lw x5, 32(x1); \
)

TEST_CASE( 31, x5, 0x0000000000000000, \
  la  x1, tdatLB; \
  addi x1, x1, -6; \
  lbu x5, 7(x1); \
)
TEST_LD_OP( 32, lbu, 0x00000000000000ff, 0,  tdatLB );
TEST_LD_OP( 33, lbu, 0x0000000000000000, 1,  tdatLB );
TEST_LD_OP( 34, lbu, 0x00000000000000f0, 2,  tdatLB );
TEST_LD_OP( 35, lbu, 0x000000000000000f, 3, tdatLB );
TEST_LD_OP( 36, lbu, 0x00000000000000ff, -3, tdat4LB );
TEST_LD_OP( 37, lbu, 0x0000000000000000, -2,  tdat4LB );
TEST_LD_OP( 38, lbu, 0x00000000000000f0, -1,  tdat4LB );
TEST_LD_OP( 39, lbu, 0x000000000000000f, 0,   tdat4LB);
TEST_CASE( 40, x5, 0x00000000000000ff, \
  la  x1, tdatLB; \
  addi x1, x1, -32; \
  lbu x5, 32(x1); \
)

TEST_CASE( 41, x5, 0x000000000000ff00, \
  la  x1, tdatLH; \
  addi x1, x1, -5; \
  lhu x5, 7(x1); \
)
TEST_LD_OP( 42, lhu, 0x00000000000000ff, 0,  tdatLH );
TEST_LD_OP( 43, lhu, 0x000000000000ff00, 2,  tdatLH );
TEST_LD_OP( 44, lhu, 0x0000000000000ff0, 4,  tdatLH );
TEST_LD_OP( 45, lhu, 0x000000000000f00f, 6, tdatLH );
TEST_LD_OP( 46, lhu, 0x00000000000000ff, -6,  tdat4LH );
TEST_LD_OP( 47, lhu, 0x000000000000ff00, -4,  tdat4LH );
TEST_LD_OP( 48, lhu, 0x0000000000000ff0, -2,  tdat4LH );
TEST_LD_OP( 49, lhu, 0x000000000000f00f,  0, tdat4LH );
TEST_CASE( 50, x5, 0x00000000000000ff, \
  la  x1, tdatLH; \
  addi x1, x1, -32; \
  lhu x5, 32(x1); \
)

TEST_CASE( 51, x5, 0x00000000ff00ff00, \
  la  x1, tdatLW; \
  addi x1, x1, -3; \
  lwu x5, 7(x1); \
)
TEST_LD_OP( 52, lwu, 0x0000000000ff00ff, 0,  tdatLW );
TEST_LD_OP( 53, lwu, 0x00000000ff00ff00, 4,  tdatLW );
TEST_LD_OP( 54, lwu, 0x000000000ff00ff0, 8,  tdatLW );
TEST_LD_OP( 55, lwu, 0x00000000f00ff00f, 12, tdatLW );
TEST_LD_OP( 56, lwu, 0x0000000000ff00ff, -12, tdat4LW );
TEST_LD_OP( 57, lwu, 0x00000000ff00ff00, -8,  tdat4LW );
TEST_LD_OP( 58, lwu, 0x000000000ff00ff0, -4,  tdat4LW );
TEST_LD_OP( 59, lwu, 0x00000000f00ff00f, 0,   tdat4LW );
TEST_CASE( 60, x5, 0x0000000000ff00ff, \
  la  x1, tdatLW; \
  addi x1, x1, -32; \
  lwu x5, 32(x1); \
)

TEST_ST_OP( 61, lb, sb, 0x000000000000000a, -3,  tdat4LB );
TEST_ST_OP( 62, lb, sb, 0xffffffffffffffaa, 0, tdatLB );
TEST_ST_OP( 63, lb, sb, 0x0000000000000000, 1, tdatLB );
TEST_ST_OP( 64, lb, sb, 0xffffffffffffffa0, 2, tdatLB );
TEST_ST_OP( 65, lb, sb, 0x000000000000000a, 3, tdatLB );
TEST_ST_OP( 66, lb, sb, 0xffffffffffffffaa, 0, tdat4LB );
TEST_ST_OP( 67, lb, sb, 0x0000000000000000, -1, tdat4LB );
TEST_ST_OP( 68, lb, sb, 0xffffffffffffffa0, -2, tdat4LB );

TEST_ST_OP( 69, lh, sh, 0xffffffffffffa00a, -6,  tdat4LH );
TEST_ST_OP( 70, lh, sh, 0x0000000000000aa0, -4, tdat4LH );
TEST_ST_OP( 71, lh, sh, 0xffffffffffffa00a, -6,  tdat4LH );
TEST_ST_OP( 72, lh, sh, 0x00000000000000aa, 0, tdatLH );
TEST_ST_OP( 73, lh, sh, 0xffffffffffffaa00, 2, tdatLH );
TEST_ST_OP( 74, lh, sh, 0x0000000000000aa0, 4, tdatLH );
TEST_ST_OP( 75, lh, sh, 0xffffffffffffa00a, 6, tdatLH );
TEST_ST_OP( 76, lh, sh, 0x00000000000000aa, 0, tdat4LH );
TEST_ST_OP( 77, lh, sh, 0xffffffffffffaa00, -2, tdat4LH );

TEST_ST_OP( 78, lw, sw, 0x000000000aa00aa0, -8,  tdat4LW );
TEST_ST_OP( 79, lw, sw, 0xffffffffa00aa00a, -12,   tdat4LW );
TEST_ST_OP( 80, lw, sw, 0x0000000000aa00aa, 0, tdat4LW );
TEST_ST_OP( 81, lw, sw, 0xffffffffaa00aa00, -4,  tdat4LW );
TEST_ST_OP( 82, lw, sw, 0x0000000000aa00aa, 0,  tdatLW );
TEST_ST_OP( 83, lw, sw, 0xffffffffaa00aa00, 4,  tdatLW );
TEST_ST_OP( 84, lw, sw, 0x000000000aa00aa0, 8,  tdatLW );
TEST_ST_OP( 85, lw, sw, 0xffffffffa00aa00a, 12, tdatLW );

test_86:
  li  TESTNUM, 86
  la  t0, target_86

  jalr t0, t0, 0
linkaddr_86:
  j fail

target_86:
  la  t1, linkaddr_86
  bne t0, t1, fail

TEST_IMM_OP( 87, slliw, 0xffffffff93456780, 0x0000000099345678, 4 );
TEST_IMM_OP( 88, slliw, 0xffffffff80000000, 0xffffffffffffffff, 31 );
TEST_IMM_OP( 89, slliw, 0x0000000023456780, 0xffffffff12345678, 4 );

TEST_IMM_OP( 90,  srliw, 0x0000000000000001, 0xffffffff80000001, 31 );
TEST_IMM_OP( 91, srliw, 0x0000000010909090, 0x0000000021212121, 1  );
TEST_IMM_OP( 92, srliw, 0x0000000009234567, 0x0000000092345678, 4 );

TEST_IMM_OP( 93, sraiw, 0xfffffffffffe0606, 0xffffffff81818181, 14 );
TEST_IMM_OP( 94, sraiw, 0xfffffffff9234567, 0x0000000092345678, 4 );

TEST_RR_OP( 95, addw, 0xffffffff80007ffe, 0x000000007fffffff, 0x0000000000007fff );
TEST_RR_OP( 96, addw, 0xffffffff80000000, 0x0000000000000001, 0x000000007fffffff );

TEST_RR_OP( 97, subw, 0x0000000000000001, 0x0000000000000000, 0xffffffffffffffff );
TEST_RR_OP( 98,  subw, 0xffffffff80000000, 0xffffffff80000000, 0x0000000000000000 );

TEST_RR_OP( 99, sllw, 0xffffffff80000000, 0x0000000021212121, 31 );
TEST_RR_OP( 100, sllw, 0x0000000048484000, 0x0000000021212121, 0xffffffffffffffee );
TEST_RR_OP( 101, sllw, 0x0000000023456780, 0xffffffff12345678, 4 );

TEST_RR_OP( 102, srlw, 0x0000000000008484, 0x0000000021212121, 14 );
TEST_RR_OP( 103, srlw, 0x0000000010909090, 0x0000000021212121, 0xffffffffffffffe1 );
TEST_RR_OP( 104, srlw, 0x0000000001234567, 0xffffffff12345678, 4 );

TEST_RR_OP( 105, sraw, 0xfffffffffffe0606, 0xffffffff81818181, 14 );
TEST_RR_OP( 106, sraw, 0xffffffffff030303, 0xffffffff81818181, 0xffffffffffffffe7 );
TEST_RR_OP( 107, sraw, 0x0000000001234567, 0xffffffff12345678, 4 );

TEST_PASSFAIL

.section .data

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