#ifndef __DEF_H__
#define __DEF_H__

typedef unsigned long uint64_t;
#define csr_read(csr)                                        \
  ({                                                         \
    register uint64_t __v;                                   \
    asm volatile("csrr %0, " #csr : "=r"(__v) : : "memory"); \
    __v;                                                     \
  })

#define csr_write(csr, val)                                    \
  ({                                                           \
    uint64_t __v = (uint64_t)(val);                            \
    asm volatile("csrw " #csr ", %0" : : "r"(__v) : "memory"); \
  })

#endif
