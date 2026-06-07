#ifndef __PRIVATE_KDEFS_H__
#define __PRIVATE_KDEFS_H__

// QEMU virt 机器的时钟频率为 10 MHz
#define TIMECLOCK 10000000

#define PHY_START 0x80000000
#define PHY_SIZE 0x400000 // 4 MiB
#define PHY_END (PHY_START + PHY_SIZE)

#define PGSIZE 0x1000 // 4 KiB
#define PGROUNDDOWN(addr) ((addr) & ~(PGSIZE - 1))
#define PGROUNDUP(addr) PGROUNDDOWN((addr) + PGSIZE - 1)

#define OPENSBI_SIZE 0x200000

#define VM_START 0xffffffe000000000
#define VM_END 0xffffffff00000000
#define VM_SIZE (VM_END - VM_START)

#define PA2VA_OFFSET (VM_START - PHY_START)

#define USER_START 0x0
#define USER_END 0x4000000000

#define SSTATUS_SIE (1 << 1)
#define SSTATUS_SPIE (1 << 5)
#define SSTATUS_SPP (1 << 8)
#define SSTATUS_SUM (1 << 18)

#define OFFSET_THREAD 32 // 4 * 8byte
#define TASK_THREAD_RA 32
#define TASK_THREAD_SP 40
#define TASK_THREAD_S0 48
#define TASK_THREAD_S1 56
#define TASK_THREAD_S2 64
#define TASK_THREAD_S3 72
#define TASK_THREAD_S4 80
#define TASK_THREAD_S5 88
#define TASK_THREAD_S6 96
#define TASK_THREAD_S7 104
#define TASK_THREAD_S8 112
#define TASK_THREAD_S9 120
#define TASK_THREAD_S10 128
#define TASK_THREAD_S11 136
#define TASK_THREAD_SEPC 144
#define TASK_THREAD_SSTATUS 152
#define TASK_THREAD_SSCRATCH 160
#define TASK_THREAD_STVAL 168
#define TASK_THREAD_SCAUSE 176
#define TASK_PGD 184

#define PT_X0 0
#define PT_RA 8
#define PT_SP 16
#define PT_GP 24
#define PT_TP 32
#define PT_T0 40
#define PT_T1 48
#define PT_T2 56
#define PT_S0 64
#define PT_S1 72
#define PT_A0 80
#define PT_A1 88
#define PT_A2 96
#define PT_A3 104
#define PT_A4 112
#define PT_A5 120
#define PT_A6 128
#define PT_A7 136
#define PT_S2 144
#define PT_S3 152
#define PT_S4 160
#define PT_S5 168
#define PT_S6 176
#define PT_S7 184
#define PT_S8 192
#define PT_S9 200
#define PT_S10 208
#define PT_S11 216
#define PT_T3 224
#define PT_T4 232
#define PT_T5 240
#define PT_T6 248
#define PT_SEPC 256
#define PT_SIZE 272

#endif
