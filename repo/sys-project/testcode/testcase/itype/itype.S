#include "../test_macros.h"

.section .text
.globl _start

_start:

#-------------------------------------------------------------
# ADDI
#-------------------------------------------------------------

TEST_IMM_OP( 1,  addi, 0x00000000, 0x00000000, 0x000 );
TEST_IMM_OP( 2,  addi, 0x00000002, 0x00000001, 0x001 );
TEST_IMM_OP( 3,  addi, 0x0000000a, 0x00000003, 0x007 );
TEST_IMM_SRC1_EQ_DEST( 4, addi, 24, 13, 11 );
TEST_IMM_ZEROSRC1( 5, addi, 32, 32 );
TEST_IMM_ZERODEST( 6, addi, 33, 50 );

#-------------------------------------------------------------
# SLTI
#-------------------------------------------------------------

TEST_IMM_OP( 7,  slti, 0, 0x0000000000000000, 0x000 );
TEST_IMM_OP( 8,  slti, 0, 0x0000000000000001, 0x001 );
TEST_IMM_OP( 9,  slti, 1, 0x0000000000000003, 0x007 );
TEST_IMM_SRC1_EQ_DEST( 10, slti, 1, 11, 13 );
TEST_IMM_ZEROSRC1( 11, slti, 0, 0xfff );
TEST_IMM_ZERODEST( 12, slti, 0xf0, 0x0f );

#-------------------------------------------------------------
# SLTIU
#-------------------------------------------------------------

TEST_IMM_OP( 13,  sltiu, 0, 0x0000000000000000, 0x000 );
TEST_IMM_OP( 14,  sltiu, 0, 0x0000000000000001, 0x001 );
TEST_IMM_OP( 15,  sltiu, 1, 0x0000000000000003, 0x007 );
TEST_IMM_SRC1_EQ_DEST( 16, sltiu, 1, 11, 13 );
TEST_IMM_ZEROSRC1( 17, sltiu, 1, 0xfff );
TEST_IMM_ZERODEST( 18, sltiu, 0xff, 0xf0 );

#-------------------------------------------------------------
# XORI
#-------------------------------------------------------------

TEST_IMM_OP( 19, xori, 0x0f, 0x00, 0x0f );
TEST_IMM_OP( 20, xori, 0xf0, 0xff, 0x0f );
TEST_IMM_OP( 21, xori, 0xff, 0x0f, 0xf0 );
TEST_IMM_SRC1_EQ_DEST( 22, xori, 0x0f, 0x00, 0x0f );
TEST_IMM_ZEROSRC1( 23, xori, 0xf0, 0xf0 );
TEST_IMM_ZERODEST( 24, xori, 0xff, 0x0f );

#-------------------------------------------------------------
# ORI
#-------------------------------------------------------------

TEST_IMM_OP( 25, ori, 0xf0, 0xf0, 0xf0 );
TEST_IMM_OP( 26, ori, 0xff, 0xff, 0x0f );
TEST_IMM_OP( 27, ori, 0xff, 0x0f, 0xf0 )
TEST_IMM_SRC1_EQ_DEST( 28, ori, 0xf0, 0x00, 0xf0 );
TEST_IMM_ZEROSRC1( 29, ori, 0xf0, 0xf0 );
TEST_IMM_ZERODEST( 30, ori, 0xff, 0x0f );

#-------------------------------------------------------------
# ANDI
#-------------------------------------------------------------

TEST_IMM_OP( 31, andi, 0xf0, 0xf0, 0xf0 );
TEST_IMM_OP( 32, andi, 0x0f, 0xff, 0x0f );
TEST_IMM_OP( 33, andi, 0x00, 0x0f, 0xf0 );
TEST_IMM_SRC1_EQ_DEST( 34, andi, 0x00, 0x00, 0xf0 );
TEST_IMM_ZEROSRC1( 35, andi, 0, 0xf0 );
TEST_IMM_ZERODEST( 36, andi, 0xff, 0x0f );

#-------------------------------------------------------------
# SLLI
#-------------------------------------------------------------

TEST_IMM_OP( 37,  slli, 0x0000000000000001, 0x0000000000000001, 0  );
TEST_IMM_OP( 38,  slli, 0x0000000000000002, 0x0000000000000001, 1  );
TEST_IMM_OP( 39,  slli, 0x0000000000000080, 0x0000000000000001, 7  );
TEST_IMM_OP( 40,  slli, 0x0000000000004000, 0x0000000000000001, 14 );
TEST_IMM_SRC1_EQ_DEST( 41, slli, 0x00000080, 0x00000001, 7 );
TEST_IMM_ZERODEST( 42, slli, 33, 20 );

#-------------------------------------------------------------
# SRLI
#-------------------------------------------------------------

#define TEST_SRLI(n, v, a) \
  TEST_IMM_OP(n, srli, ((v) & ((1 << (64-1) << 1) - 1)) >> (a), v, a)
TEST_SRLI( 43,  0x20f, 1  );
TEST_SRLI( 44,  0x20f, 7  );
TEST_SRLI( 45,  0x20f, 14 );
TEST_IMM_SRC1_EQ_DEST( 46, srli, 0x008, 0x400, 7 );
TEST_IMM_ZEROSRC1( 47, srli, 0, 4 );
TEST_IMM_ZERODEST( 48, srli, 33, 10 );

#-------------------------------------------------------------
# SRAI
#-------------------------------------------------------------

TEST_IMM_OP( 49,  srai, 0xff, 0xff, 0  );
TEST_IMM_OP( 50,  srai, 0x7e, 0xfc, 1  );
TEST_IMM_OP( 51,  srai, 0x1, 0xff, 7  );
TEST_IMM_OP( 52, srai, 0xc0, 0x181, 1  );
TEST_IMM_ZEROSRC1( 53, srai, 0, 4 );
TEST_IMM_ZERODEST( 54, srai, 33, 10 );

#-------------------------------------------------------------
# LD
#-------------------------------------------------------------

TEST_LD_OP( 55, ld, 0xFF, 24, tdat );
TEST_LD_OP( 56, ld, 0xAB, 8,  tdat );
TEST_LD_OP( 57, ld, 0xDE, -24, tdat4 );
TEST_LD_OP( 58, ld, 0xCD, -8, tdat4 );
TEST_CASE( 59, x5, 0xDE, \
  la  x1, tdat; \
  addi x1, x1, -32; \
  ld x5, 32(x1); \
)
TEST_CASE( 60, x5, 0xAB, \
  la  x1, tdat; \
  addi x1, x1, -3; \
  ld x5, 11(x1); \
)

TEST_PASSFAIL

.section .data

tdat:
tdat1:  .dword 0xDE
tdat2:  .dword 0xAB
tdat3:  .dword 0xCD
tdat4:  .dword 0xFF