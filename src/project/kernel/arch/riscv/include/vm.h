#ifndef __VM_H__
#define __VM_H__

#include <private_kdefs.h>
#include <stdint.h>

#define PTE_V (1UL << 0)
#define PTE_R (1UL << 1)
#define PTE_W (1UL << 2)
#define PTE_X (1UL << 3)
#define PTE_U (1UL << 4)
#define PTE_A (1UL << 6)
#define PTE_D (1UL << 7)
#define PTE_S (1UL << 8)

#define PTE_FLAGS_MASK 0x3ffUL
#define PTE2PA(pte) ((((uint64_t)(pte)) >> 10) << 12)
#define PA2PTE(pa) ((((uint64_t)(pa)) >> 12) << 10)

/**
 * @brief 设置内核初始化阶段的页表映射关系
 */
void setup_vm(void);

/**
 * @brief 设置内核最终的页表映射关系
 */
void setup_vm_final(void);

/**
 * @brief 创建多级页表映射关系
 *
 * 在指定的一段虚拟内存 va 创建映射关系，将其映射到物理内存 pa
 *
 * @param pgtbl 根页表的基地址
 * @param va 虚拟地址
 * @param pa 物理地址
 * @param sz 映射的大小
 * @param perm 映射的读写权限
 */
void create_mapping(uint64_t pgtbl[static PGSIZE / 8], void *va, void *pa, uint64_t sz, uint64_t perm);

/**
 * @brief 查找 va 对应的叶子页表项。
 *
 * @return 若三级页表路径存在则返回 PTE 指针，否则返回 NULL。
 */
uint64_t *walk_page_table(uint64_t pgtbl[static PGSIZE / 8], void *va);

#endif
