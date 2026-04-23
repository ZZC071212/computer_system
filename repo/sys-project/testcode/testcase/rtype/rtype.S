#include "../test_macros.h"

.section .text
.globl _start

_start:

#-------------------------------------------------------------
# ADD
#-------------------------------------------------------------

TEST_RR_ZERODEST( 1, add, 16, 30 );
TEST_RR_OP( 2,  add, 0x00000000, 0x00000000, 0x00000000 );
TEST_RR_OP( 3,  add, 0x00000002, 0x00000001, 0x00000001 );
TEST_RR_OP( 4,  add, 0x0000000a, 0x00000003, 0x00000007 );
TEST_RR_ZEROSRC12( 5, add, 0 );
TEST_RR_SRC1_EQ_DEST( 6, add, 24, 13, 11 );
TEST_RR_SRC12_EQ_DEST( 7, add, 26, 13 );
TEST_RR_ZEROSRC1( 8, add, 15, 15 );
TEST_RR_ZEROSRC2( 9, add, 32, 32 );

#-------------------------------------------------------------
# SUB
#-------------------------------------------------------------

TEST_RR_ZEROSRC1( 10, sub, 15, -15 );
TEST_RR_SRC1_EQ_DEST( 11, sub, 2, 13, 11 );
TEST_RR_SRC2_EQ_DEST( 12, sub, 3, 14, 11 );
TEST_RR_SRC12_EQ_DEST( 13, sub, 0, 13 );
TEST_RR_ZEROSRC2( 14, sub, 32, 32 );
TEST_RR_ZEROSRC12( 15, sub, 0 );
TEST_RR_ZERODEST( 16, sub, 16, 30 );

#-------------------------------------------------------------
# SLL
#-------------------------------------------------------------

TEST_RR_SRC1_EQ_DEST( 17, sll, 0x00000080, 0x00000001, 7  );
TEST_RR_SRC2_EQ_DEST( 18, sll, 0x00004000, 0x00000001, 14 );
TEST_RR_SRC12_EQ_DEST( 19, sll, 24, 3 );
TEST_RR_ZEROSRC2( 20, sll, 32, 32 );
TEST_RR_ZEROSRC1( 21, sll, 0, 15 );
TEST_RR_ZEROSRC12( 22, sll, 0 );

#-------------------------------------------------------------
# SLT
#-------------------------------------------------------------

TEST_RR_SRC1_EQ_DEST( 23, slt, 0, 14, 13 );
TEST_RR_SRC2_EQ_DEST( 24, slt, 1, 11, 13 );
TEST_RR_SRC12_EQ_DEST( 25, slt, 0, 13 );
TEST_RR_ZEROSRC1( 26, slt, 0, -1 );
TEST_RR_ZEROSRC2( 27, slt, 1, -1 );
TEST_RR_ZEROSRC12( 28, slt, 0 );
TEST_RR_ZERODEST( 29, slt, 16, 30 );

#-------------------------------------------------------------
# SLTU
#-------------------------------------------------------------

TEST_RR_SRC1_EQ_DEST( 30, sltu, 0, 14, 13 );
TEST_RR_SRC2_EQ_DEST( 31, sltu, 1, 11, 13 );
TEST_RR_SRC12_EQ_DEST( 32, sltu, 0, 13 );
TEST_RR_ZEROSRC1( 33, sltu, 1, -1 );
TEST_RR_ZEROSRC2( 34, sltu, 0, -1 );
TEST_RR_ZEROSRC12( 35, sltu, 0 );
TEST_RR_ZERODEST( 36, sltu, 16, 30 );

#-------------------------------------------------------------
# XOR
#-------------------------------------------------------------

TEST_RR_OP( 37, xor, 0xf0, 0xff, 0x0f );
TEST_RR_OP( 38, xor, 0xff, 0x0f, 0xf0 );
TEST_RR_SRC1_EQ_DEST( 39, xor, 0x0f, 0x00, 0x0f );
TEST_RR_ZEROSRC12( 40, xor, 0 );
TEST_RR_ZERODEST( 41, xor, 0x11, 0x22 );

#-------------------------------------------------------------
# SRL
#-------------------------------------------------------------

#define TEST_SRL(n, v, a) \
  TEST_RR_OP(n, srl, ((v) & ((1 << (64-1) << 1) - 1)) >> (a), v, a)

TEST_RR_SRC12_EQ_DEST( 42, srl, 0, 7 );
TEST_RR_ZEROSRC1( 43, srl, 0, 15 );
TEST_RR_ZEROSRC2( 44, srl, 32, 32 );
TEST_RR_ZEROSRC12( 45, srl, 0 );

#-------------------------------------------------------------
# SRA
#-------------------------------------------------------------

TEST_RR_SRC12_EQ_DEST( 46, sra, 0, 7 );
TEST_RR_ZEROSRC1( 47, sra, 0, 15 );
TEST_RR_ZEROSRC2( 48, sra, 32, 32 );
TEST_RR_ZEROSRC12( 49, sra, 0 );

#-------------------------------------------------------------
# OR
#-------------------------------------------------------------

TEST_RR_SRC1_EQ_DEST( 50, or, 0x0f, 0x00, 0x0f );
TEST_RR_OP( 51, or, 0xff, 0x0f, 0xf0 );
TEST_RR_ZERODEST( 52, or, 0x11, 0x22 );

#-------------------------------------------------------------
# AND
#-------------------------------------------------------------
TEST_RR_OP( 53, and, 0x0f, 0xff, 0x0f );
TEST_RR_OP( 54, and, 0x00, 0x0f, 0xf0 );
TEST_RR_ZEROSRC12( 55, and, 0 );
TEST_RR_ZERODEST( 56, and, 0x11, 0x22 );

TEST_PASSFAIL
