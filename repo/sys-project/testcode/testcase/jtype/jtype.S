#include "../test_macros.h"

.section .text
.globl _start

_start:

test_1:
  li  TESTNUM, 1
  li  ra, 0

  jal x4, target_2

linkaddr_2:
  nop
  nop
  j fail

target_2:
  la  x2, linkaddr_2
  bne x2, x4, fail

  #-------------------------------------------------------------
  # Test delay slot instructions not executed nor bypassed
  #-------------------------------------------------------------

  TEST_CASE( 2, ra, 3, \
    li  ra, 1; \
    jal x0, 1f; \
    addi ra, ra, 1; \
    addi ra, ra, 1; \
    addi ra, ra, 1; \
    addi ra, ra, 1; \
1:  addi ra, ra, 1; \
    addi ra, ra, 1; \
  )

TEST_PASSFAIL