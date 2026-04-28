#include <vm.h>
#include <mm.h>
#include <printk.h>
#include <sbi.h>
#include <string.h>

#define PTE_V (1UL << 0)
#define PTE_R (1UL << 1)
#define PTE_W (1UL << 2)
#define PTE_X (1UL << 3)
#define PTE_A (1UL << 6)
#define PTE_D (1UL << 7)

#define SATP_MODE_SV39 (8UL << 60)

#define VPN2(va) ((((uint64_t)(va)) >> 30) & 0x1ff)
#define VPN1(va) ((((uint64_t)(va)) >> 21) & 0x1ff)
#define VPN0(va) ((((uint64_t)(va)) >> 12) & 0x1ff)
#define PTE2PA(pte) ((((uint64_t)(pte)) >> 10) << 12)
#define PA2PTE(pa) ((((uint64_t)(pa)) >> 12) << 10)

extern uint8_t _stext[];
extern uint8_t _etext[];
extern uint8_t _srodata[];
extern uint8_t _erodata[];
extern uint8_t _sdata[];
extern uint8_t _ekernel[];

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

  uint64_t entry = PA2PTE(PHY_START) | PTE_X | PTE_W | PTE_R | PTE_V | PTE_A | PTE_D;
  early_pgtbl[VPN2(VM_START)] = entry;
}

void setup_vm_final(void) {
  memset(swapper_pg_dir, 0, PGSIZE);

  // No OpenSBI mapping required

  // 1. 调用 create_mapping 映射页表
  //    - kernel code: X R
  //    - kernel rodata: R
  //    - other memory: W R
  // 2. 设置 satp，将 swapper_pg_dir 作为内核页表

  create_mapping(swapper_pg_dir, _stext, (void *)VA2PA(_stext),
                 (uint64_t)(_etext - _stext), PTE_X | PTE_R);
  create_mapping(swapper_pg_dir, _srodata, (void *)VA2PA(_srodata),
                 (uint64_t)(_erodata - _srodata), PTE_R);
  create_mapping(swapper_pg_dir, _sdata, (void *)VA2PA(_sdata),
                 PA2VA(PHY_END) - (uint64_t)_sdata, PTE_W | PTE_R);

  uint64_t satp = SATP_MODE_SV39 | (((uint64_t)VA2PA(swapper_pg_dir)) >> 12);
  csr_write(satp, satp);

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

  uint64_t va_start = PGROUNDDOWN((uint64_t)va);
  uint64_t va_end = PGROUNDUP((uint64_t)va + sz);
  uint64_t pa_start = PGROUNDDOWN((uint64_t)pa);

  printk("pgtbl = %#lx: map [%#lx, %#lx) -> [%#lx, %#lx), perm = %#lx, size = %lu\n",
         VA2PA(pgtbl), va_start, va_end, pa_start, pa_start + (va_end - va_start),
         perm, va_end - va_start);

  for (uint64_t cur_va = va_start, cur_pa = pa_start; cur_va < va_end;
       cur_va += PGSIZE, cur_pa += PGSIZE) {
    uint64_t *level2 = pgtbl;
    uint64_t vpn[3] = {VPN0(cur_va), VPN1(cur_va), VPN2(cur_va)};

    for (int level = 2; level > 0; --level) {
      uint64_t *pte = &level2[vpn[level]];
      if (!(*pte & PTE_V)) {
        uint64_t *new_page = alloc_page();
        memset(new_page, 0, PGSIZE);
        *pte = PA2PTE(VA2PA(new_page)) | PTE_V;
      }
      level2 = (uint64_t *)PA2VA(PTE2PA(*pte));
    }

    level2[vpn[0]] = PA2PTE(cur_pa) | perm | PTE_V | PTE_A | PTE_D;
  }
}
