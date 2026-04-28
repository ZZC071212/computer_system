#ifndef __MM_H__
#define __MM_H__

#include <private_kdefs.h>
#include <stdint.h>
#include <stddef.h>

#define VA2PA(x) ((uint64_t)(x) - PA2VA_OFFSET)
#define PA2VA(x) ((uint64_t)(x) + PA2VA_OFFSET)
#define PFN2PHYS(x) (((uint64_t)(x) << 12) + PHY_START)
#define PHYS2PFN(x) (((uint64_t)(x) - PHY_START) >> 12)

/**
 * @brief 内存管理初始化函数
 */
void mm_init(void);

/**
 * @brief 分配物理内存；保证分配的内存是连续的
 *
 * @param nrpages 要分配的页数
 * @return 分配的物理内存的虚拟地址
 */
void *alloc_pages(size_t nrpages);

/**
 * @brief 分配一页物理内存
 *
 * @return 分配的物理内存的虚拟地址
 */
void *alloc_page(void);

/**
 * @brief 释放物理内存
 *
 * @param va 要释放的物理内存的虚拟地址
 */
void free_pages(void *va);

/**
 * @brief 增加页表引用计数
 *
 * @param va 要增加引用计数的物理内存的虚拟地址
 * @return 若 va 是无效的，则返回 -1；否则返回 0
 */
int ref_page(void *va);

/**
 * @brief 减少页表引用计数
 *
 * 当引用计数为 0 时，释放物理内存
 *
 * @param va 要减少引用计数的物理内存的虚拟地址
 * @return 若 va 是无效的，则返回 -1；否则返回 0
 */
int deref_page(void *va);

#endif
