#ifndef __VM_H__
#define __VM_H__

#include <private_kdefs.h>
#include <stdint.h>

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

#endif
