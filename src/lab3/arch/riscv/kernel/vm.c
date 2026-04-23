#include <vm.h>
#include <string.h>

// 用于 setup_vm 进行 1 GiB 的映射
uint64_t early_pgtbl[PGSIZE / 8] __attribute__((__aligned__(PGSIZE)));
// kernel page table 根目录，在 setup_vm_final 进行映射
uint64_t swapper_pg_dir[PGSIZE / 8] __attribute__((__aligned__(PGSIZE)));

void setup_vm(void) {
  memset(early_pgtbl, 0, PGSIZE);

  // 1. 初始化阶段，页大小为 1 GiB，不使用多级页表
  // 2. 将 va 的 64 bit 作如下划分：| 63...39 | 38...30 | 29...0 |
  //    - 63...39 bit 忽略
  //    - 38...30 bit 作为 early_pgtbl 的索引
  //    - 29...0 bit 作为页内偏移，注意到 30 = 9 + 9 + 12，即我们此处只使用根页表，根页表的每个 entry 对应 1 GiB 的页
  // 3. Page Table Entry 的权限为 X W R V

#error Not yet implemented
}

void setup_vm_final(void) {
  memset(swapper_pg_dir, 0, PGSIZE);

  // No OpenSBI mapping required

  // 1. 调用 create_mapping 映射页表
  //    - kernel code: X R
  //    - kernel rodata: R
  //    - other memory: W R
  // 2. 设置 satp，将 swapper_pg_dir 作为内核页表

#error Not yet implemented

  // flush TLB
  asm volatile("sfence.vma" ::: "memory");

  return;
}

void create_mapping(uint64_t pgtbl[static PGSIZE / 8], void *va, void *pa, uint64_t sz, uint64_t perm) {
  // TODO：根据 RISC-V Sv39 的要求，创建多级页表映射关系
  //
  // 物理内存需要分页
  // 创建多级页表的时候使用 alloc_page 来获取新的一页作为页表
  // 注意通过 V bit 来判断表项是否存在
  //
  // 重要：阅读手册，注意 A / D 位的设置

#error Not yet implemented
}
