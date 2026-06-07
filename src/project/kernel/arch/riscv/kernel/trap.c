#include <stdint.h>
#include <printk.h>
#include <proc.h>
#include <ksyscalls.h>
#include <syscalls.h>
#include <mm.h>
#include <vm.h>
#include <string.h>

void clock_set_next_event(void);

enum {
  REG_A0 = 10,
  REG_A1 = 11,
  REG_A2 = 12,
  REG_A7 = 17,
};

#define SCAUSE_INTERRUPT (1UL << 63)
#define SCAUSE_CODE_MASK (~SCAUSE_INTERRUPT)
#define SCAUSE_TIMER 5
#define SCAUSE_ECALL_U 8
#define SCAUSE_INST_PAGE_FAULT 12
#define SCAUSE_LOAD_PAGE_FAULT 13
#define SCAUSE_STORE_PAGE_FAULT 15

extern uint8_t _suapp[];
extern uint8_t _euapp[];

static int page_fault_allowed(uint64_t code, const struct vm_area_struct *vma) {
  if (code == SCAUSE_INST_PAGE_FAULT) {
    return vma->vm_flags & VM_EXEC;
  }
  if (code == SCAUSE_LOAD_PAGE_FAULT) {
    return vma->vm_flags & VM_READ;
  }
  if (code == SCAUSE_STORE_PAGE_FAULT) {
    return vma->vm_flags & VM_WRITE;
  }
  return 0;
}

static uint64_t vm_flags_to_pte_perm(unsigned flags) {
  uint64_t perm = PTE_U;
  if (flags & VM_READ) {
    perm |= PTE_R;
  }
  if (flags & VM_WRITE) {
    perm |= PTE_W;
  }
  if (flags & VM_EXEC) {
    perm |= PTE_X;
  }
  return perm;
}

static void fatal_page_fault(struct pt_regs *regs, uint64_t scause, uint64_t stval,
                             const char *reason) {
  printk("[S] fatal page fault: %s; scause = %#lx, sepc = %#lx, stval = %#lx\n",
         reason, scause, regs->sepc, stval);
  while (1) {
  }
}

static void do_page_fault(struct pt_regs *regs, uint64_t scause, uint64_t stval) {
  uint64_t code = scause & SCAUSE_CODE_MASK;//去掉最高为interrupt标记，只留下异常编号
  uint64_t va = PGROUNDDOWN(stval);
  struct vm_area_struct *vma = find_vma(current->mm, (void *)stval);

  if (!vma) {
    fatal_page_fault(regs, scause, stval, "bad address is outside all VMAs");
  }
  if (!page_fault_allowed(code, vma)) {
    fatal_page_fault(regs, scause, stval, "VMA permission check failed");
  }

  //Copy On Write处理
  uint64_t *pte = walk_page_table(current->pgd, (void *)va);
  if (code == SCAUSE_STORE_PAGE_FAULT && pte && (*pte & PTE_V) && (*pte & PTE_S)) {
    uint64_t old_pa = PTE2PA(*pte);
    void *old_page = (void *)PA2VA(old_pa);
    void *new_page = alloc_page();
    memcpy(new_page, old_page, PGSIZE);
    deref_page(old_page);

    uint64_t perm = ((*pte & PTE_FLAGS_MASK) | PTE_W) & ~(PTE_V | PTE_S);//恢复可写权限，清掉 PTE_S。
    create_mapping(current->pgd, (void *)va, (void *)VA2PA(new_page), PGSIZE, perm);//建立页表映射
    asm volatile("sfence.vma zero, zero" ::: "memory");
    return;
  }

  //权限不够
  if (pte && (*pte & PTE_V)) {
    fatal_page_fault(regs, scause, stval, "mapped page has insufficient PTE permission");
  }

  void *page = alloc_page();
  memset(page, 0, PGSIZE);

  if (!(vma->vm_flags & VM_ANON)) //如果不是匿名页，说明是用户程序区域，拷贝内核中嵌入的.uapp镜像
  {
    uint64_t uapp_size = (uint64_t)(_euapp - _suapp);
    uint64_t offset = va - USER_START;
    if (offset < uapp_size) {
      uint64_t copy_size = uapp_size - offset;
      if (copy_size > PGSIZE) {
        copy_size = PGSIZE;
      }
      memcpy(page, _suapp + offset, copy_size);
    }
  }

  create_mapping(current->pgd, (void *)va, (void *)VA2PA(page), PGSIZE,
                 vm_flags_to_pte_perm(vma->vm_flags));//把用户虚拟页映射到刚分配的物理页
  asm volatile("sfence.vma zero, zero" ::: "memory");
}

void trap_handler(struct pt_regs *regs, uint64_t scause, uint64_t stval) {
  uint64_t code = scause & SCAUSE_CODE_MASK;

  if ((scause & SCAUSE_INTERRUPT) && code == SCAUSE_TIMER) {
    clock_set_next_event();
    do_timer();
    return;
  }

  if (!(scause & SCAUSE_INTERRUPT) && code == SCAUSE_ECALL_U) {
    switch (regs->x[REG_A7]) //取系统调用号
    {
      case __NR_read:
        regs->x[REG_A0] = sys_read((unsigned)regs->x[REG_A0],
                                   (char *)regs->x[REG_A1],
                                   (size_t)regs->x[REG_A2]);
        break;
      case __NR_write:
        regs->x[REG_A0] = sys_write((unsigned)regs->x[REG_A0],
                                    (const char *)regs->x[REG_A1],
                                    (size_t)regs->x[REG_A2]);
        break;
      case __NR_getpid:
        regs->x[REG_A0] = sys_getpid();
        break;
      case __NR_clone:
        regs->x[REG_A0] = sys_clone(regs);//返回值写回a0
        break;
      default:
        printk("[trap] unknown syscall: %lu\n", regs->x[REG_A7]);
        regs->x[REG_A0] = (uint64_t)-1;
        break;
    }
    regs->sepc += 4;
    return;
  }

  if (!(scause & SCAUSE_INTERRUPT) &&
      (code == SCAUSE_INST_PAGE_FAULT ||
       code == SCAUSE_LOAD_PAGE_FAULT ||
       code == SCAUSE_STORE_PAGE_FAULT)) {
    do_page_fault(regs, scause, stval);
    return;
  }

  printk("[trap] unexpected trap! scause=%lx, sepc=%lx, stval=%lx\n",
         scause, regs->sepc, stval);
}        
