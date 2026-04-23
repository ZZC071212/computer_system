#include "../test_macros.h"

.section .text
.globl _start

_start:

TEST_ST_OP( 1, ld, sd, 0xAB, 0,  tdat );
TEST_ST_OP( 2, ld, sd, 0xCD, 8,  tdat );
TEST_ST_OP( 3, ld, sd, 0xEF, 16,  tdat );
TEST_ST_OP( 4, ld, sd, 0x12, 24, tdat );

TEST_ST_OP( 5, ld, sd, 0x34, -24, tdat8 );
TEST_ST_OP( 6, ld, sd, 0x56, -16, tdat8 );
TEST_ST_OP( 7, ld, sd, 0x78, -8,  tdat8 );
TEST_ST_OP( 8, ld, sd, 0x9A, 0,   tdat8 );

TEST_CASE( 9, x5, 0xAC, \
  la  x1, tdat9; \
  li  x2, 0xAC; \
  addi x4, x1, -32; \
  sd x2, 32(x4); \
  ld x5, 0(x1); \
)

TEST_CASE( 10, x5, 0xBD, \
  la  x1, tdat9; \
  li  x2, 0xBD; \
  addi x1, x1, -3; \
  sd x2, 11(x1); \
  la  x4, tdat10; \
  ld x5, 0(x4); \
)

TEST_PASSFAIL

.section .data

tdat:
tdat1:  .dword 0xdeadbeefdeadbeef
tdat2:  .dword 0xdeadbeefdeadbeef
tdat3:  .dword 0xdeadbeefdeadbeef
tdat4:  .dword 0xdeadbeefdeadbeef
tdat5:  .dword 0xdeadbeefdeadbeef
tdat6:  .dword 0xdeadbeefdeadbeef
tdat7:  .dword 0xdeadbeefdeadbeef
tdat8:  .dword 0xdeadbeefdeadbeef
tdat9:  .dword 0xdeadbeefdeadbeef
tdat10: .dword 0xdeadbeefdeadbeef