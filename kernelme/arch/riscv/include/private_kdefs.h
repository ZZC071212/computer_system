#ifndef __PRIVATE_KDEFS_H__
#define __PRIVATE_KDEFS_H__

// QEMU virt 机器的时钟频率为 10 MHz
#define TIMECLOCK 200000
//#define TIMECLOCK 3260
#define PHY_START 0x80000000
#define PHY_SIZE 0x400000 // 4 MiB
#define PHY_END (PHY_START + PHY_SIZE)

#define PGSIZE 0x1000 // 4 KiB
#define PGROUNDDOWN(addr) ((addr) & ~(PGSIZE - 1))
#define PGROUNDUP(addr) PGROUNDDOWN((addr) + PGSIZE - 1)

#endif
