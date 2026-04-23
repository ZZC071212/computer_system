#ifndef __SBI_TRAP_H__
#define __SBI_TRAP_H__

#include "def.h"

#define USI 0x8000000000000000
#define SSI 0x8000000000000001
#define HSI 0x8000000000000002
#define MSI 0x8000000000000003
#define UTI 0x8000000000000004
#define STI 0x8000000000000005
#define HTI 0x8000000000000006
#define MTI 0x8000000000000007
#define UEI 0x8000000000000008
#define SEI 0x8000000000000009
#define HEI 0x800000000000000a
#define MEI 0x800000000000000b

#define INST_ADDR_UNALIGN 0
#define INST_ACCESS_FAULT 1
#define ILLEGAL_INST 2
#define BREAKPOINT 3
#define LOAD_ADDR_UNALIGN 4
#define LOAD_ACCESS_FAULT 5
#define STORE_ADDR_UNALIGN 6
#define STORE_ACCESS_FAULT 7
#define U_CALL 8
#define S_CALL 9
#define H_CALL 10
#define M_CALL 11

struct sbi_pr_reg {
  union {
    struct {
      uint64_t zero;
      uint64_t ra;
      uint64_t sp;
      uint64_t gp;
      uint64_t tp;
      uint64_t t0;
      uint64_t t1;
      uint64_t t2;
      uint64_t s0;
      uint64_t s1;
      uint64_t a0;
      uint64_t a1;
      uint64_t a2;
      uint64_t a3;
      uint64_t a4;
      uint64_t a5;
      uint64_t a6;
      uint64_t a7;
      uint64_t s2;
      uint64_t s3;
      uint64_t s4;
      uint64_t s5;
      uint64_t s6;
      uint64_t s7;
      uint64_t s8;
      uint64_t s9;
      uint64_t s10;
      uint64_t s11;
      uint64_t t3;
      uint64_t t4;
      uint64_t t5;
      uint64_t t6;
    };
    uint64_t x[32];
  };
  uint64_t mepc;
};

void sbi_trap_handler(uint64_t mcause, struct sbi_pr_reg *pr_reg);

#endif
