#include "sbi_trap.h"
#include "mcsr.h"
#include "def.h"
#include "uart.h"

#define EID_FID(eid, fid) (((uint64_t)eid << 32) | fid)

static void sbi_set_timer(uint64_t time) {
  csr_write(mip, csr_read(mip) & ~MIP_STIP);
  csr_write(mie, csr_read(mie) | MIE_MTIE);
  *(volatile uint64_t *)MTIMECMP = (*(volatile uint64_t *)MTIME > time) ? (*(volatile uint64_t *)MTIME + time) : time;
}

static inline void sbi_debug_console_write_byte(uint64_t c) {
  return uart_tx(c);
}

static void sbi_debug_console_write(unsigned long num_bytes, unsigned long base_addr_lo, unsigned long base_addr_hi) {
  char *s = (char *)base_addr_lo;
  while (num_bytes--) {
    sbi_debug_console_write_byte(*s++);
  }
}

void sbi_scall_handler(struct sbi_pr_reg *pr_reg) {
  uint64_t fid = pr_reg->a6;
  uint64_t eid = pr_reg->a7;
  uint64_t arg0 = pr_reg->a0;
  uint64_t arg1 = pr_reg->a1;
  uint64_t arg2 = pr_reg->a2;
  uint64_t arg3 = pr_reg->a3;
  uint64_t arg4 = pr_reg->a4;
  uint64_t arg5 = pr_reg->a5;

  if (eid < 0x10) {
    // legacy extensions follow different calling convention
    switch (eid) {
      case 0x00:
        // Extension: Set Timer
        sbi_set_timer(arg0);
        pr_reg->a0 = 0;
        break;
      case 0x01:
        // Extension: Console Putchar
        sbi_debug_console_write_byte(arg0);
        pr_reg->a0 = 0;
        break;
    }
  } else {
    switch (EID_FID(eid, fid)) {
      case EID_FID(0x54494d45, 0):
        // "TIME": Set Timer
        sbi_set_timer(arg0);
        pr_reg->a0 = 0;
        pr_reg->a1 = 0;
        break;
      case EID_FID(0x4442434e, 0):
        // "DBCN": Debug Console Write
        sbi_debug_console_write(arg0, arg1, arg2);
        pr_reg->a0 = 0;
        pr_reg->a1 = arg0;
        break;
      case EID_FID(0x4442434e, 1):
        // "DBCN": Debug Console Read
        pr_reg->a0 = -4; // SBI_ERR_DENIED
        pr_reg->a1 = 0;
        break;
      case EID_FID(0x4442434e, 2):
        // "DBCN": Debug Console Write Byte
        sbi_debug_console_write_byte(arg0);
        pr_reg->a0 = 0;
        pr_reg->a1 = 0;
        break;
    }
  }

  pr_reg->mepc += 4;
}

void sbi_mti_handler(struct sbi_pr_reg *pr_reg) {
  csr_write(mip, csr_read(mip) | MIP_STIP);
  csr_write(mie, csr_read(mie) & ~MIE_MTIE);
}

void sbi_trap_handler(uint64_t mcause, struct sbi_pr_reg *pr_reg) {
  switch (mcause) {
    case S_CALL:
      sbi_scall_handler(pr_reg);
      break;
    case MTI:
      sbi_mti_handler(pr_reg);
      break;
  }
}
