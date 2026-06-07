#include <mm.h>
#include <vm.h>
#include <proc.h>
#include <private_kdefs.h>
#include <printk.h>
#include <sbi.h>
#include <stdlib.h>
#include <string.h>

static struct task_struct *task[NR_TASKS]; // 线程数组，所有的线程都保存在此
static size_t nr_tasks;                    // 当前已经创建的线程数
static struct task_struct *idle;           // idle 线程
struct task_struct *current;               // 当前运行线程

extern uint64_t swapper_pg_dir[PGSIZE / 8];
extern uint8_t _suapp[];
extern uint8_t _euapp[];

void __dummy(void);
void __switch_to(struct task_struct *prev, struct task_struct *next);
void ret_from_fork(void);

#define PFH1 1001
#define PFH2 1002
#define FORK1 1101
#define FORK2 1102
#define FORK3 1103
#define FORK4 1104

#ifndef USER_MAIN
#define USER_MAIN PFH1
#endif

#if USER_MAIN == PFH1 || USER_MAIN == PFH2
#define INIT_USER_TASKS 4
#else
#define INIT_USER_TASKS 1
#endif

struct vm_area_struct *find_vma(struct mm_struct *mm, void *va) {
    if (!mm) {
        return 0;
    }

    uint64_t addr = (uint64_t)va;
    for (struct vm_area_struct *vma = mm->mmap; vma; vma = vma->vm_next) {
        if ((uint64_t)vma->vm_start <= addr && addr < (uint64_t)vma->vm_end) //查找的地址在当前vma块中
        {
            return vma;
        }
    }
    return 0;
}


//只是给某个进程的虚拟空间mm_struct添加一段合法的虚拟内存区域vma,并不真正分配用户页，不会建立页表映射，在pagefault时才添加
void *do_mmap(struct mm_struct *mm, void *va, size_t len, unsigned flags) {
    if (!mm || len == 0) {
        return 0;
    }

    struct vm_area_struct *vma = alloc_page();
    memset(vma, 0, PGSIZE);
    vma->vm_mm = mm;//记录这个vma属于哪个进程的虚拟地址空间
    vma->vm_start = va;
    vma->vm_end = (void *)((uint64_t)va + len);
    vma->vm_flags = flags;

    struct vm_area_struct *prev = 0;
    struct vm_area_struct *cur = mm->mmap;//从链表头开始遍历，找到第一个vm_start大于va的vma
    while (cur && (uint64_t)cur->vm_start < (uint64_t)va) {
        prev = cur;
        cur = cur->vm_next;
    }

    vma->vm_prev = prev;
    vma->vm_next = cur;
    if (prev) {
        prev->vm_next = vma;
    } else {
        mm->mmap = vma;
    }
    if (cur) {
        cur->vm_prev = vma;
    }
//返回这段vma的初始虚拟地址
    return va;
}

static pagetable_t setup_user_pagetable(void) {
    pagetable_t pgd = alloc_page();//分配一页作为用户进程的根页表
    memset(pgd, 0, PGSIZE);
    memcpy(pgd, swapper_pg_dir, PGSIZE);//复制内核页表
    return pgd;
}//但没有用户代码，用户栈的实际映射

static struct mm_struct *setup_user_mm(void) //创建合法虚拟地址范围记录
{
    struct mm_struct *mm = alloc_page();
    memset(mm, 0, PGSIZE);

    do_mmap(mm, (void *)USER_START, (size_t)(_euapp - _suapp),
            VM_READ | VM_WRITE | VM_EXEC);//用户程序区域
    do_mmap(mm, (void *)(USER_END - PGSIZE), PGSIZE,
            VM_READ | VM_WRITE | VM_ANON);//用户栈区域 VM_ANON 表示匿名页
    return mm;
}

static struct mm_struct *copy_mm(struct mm_struct *src)//复制vma链表
 {
    struct mm_struct *dst = alloc_page();
    memset(dst, 0, PGSIZE);//分配一个新的mm

    for (struct vm_area_struct *vma = src->mmap; vma; vma = vma->vm_next) {
        do_mmap(dst, vma->vm_start,
                (size_t)((uint64_t)vma->vm_end - (uint64_t)vma->vm_start),
                vma->vm_flags);
    }
    return dst;
}

static void share_present_pages(struct task_struct *parent, struct task_struct *child) {
    for (struct vm_area_struct *vma = parent->mm->mmap; vma; vma = vma->vm_next) {
        uint64_t start = PGROUNDDOWN((uint64_t)vma->vm_start);
        uint64_t end = PGROUNDUP((uint64_t)vma->vm_end);

        for (uint64_t va = start; va < end; va += PGSIZE) {
            uint64_t *pte = walk_page_table(parent->pgd, (void *)va);
            if (!pte || !(*pte & PTE_V) || !(*pte & (PTE_R | PTE_W | PTE_X))) {
                continue;
            }

            uint64_t pa = PTE2PA(*pte);
            uint64_t perm = *pte & PTE_FLAGS_MASK;
            if (perm & PTE_W) {
                perm = (perm & ~PTE_W) | PTE_S;
            }
            perm &= ~PTE_V;

            ref_page((void *)PA2VA(pa));
            create_mapping(parent->pgd, (void *)va, (void *)pa, PGSIZE, perm);
            create_mapping(child->pgd, (void *)va, (void *)pa, PGSIZE, perm);
        }
    }

    asm volatile("sfence.vma zero, zero" ::: "memory");
}

void task_init(void) {
    srand(2025);
    nr_tasks = 0;

    idle = alloc_page();
    memset(idle, 0, PGSIZE);

    idle->state = TASK_RUNNING;
    idle->pid = 0;
    idle->priority = 0;
    idle->counter = 0;
    idle->pgd = swapper_pg_dir;
    idle->mm = 0;
    current = idle;
    task[nr_tasks++] = idle;

    for (int i = 0; i < INIT_USER_TASKS && nr_tasks < NR_TASKS; i ++){//创建用户进程
        struct task_struct *p = alloc_page();
        memset(p, 0, PGSIZE);
        p->state = TASK_RUNNING;
        p->pid = nr_tasks;
        uint64_t priority = rand() % (PRIORITY_MAX - PRIORITY_MIN + 1) + PRIORITY_MIN;
        p->priority = priority;
        p->counter = 0;

        p->thread.ra = (uint64_t)__dummy;
        p->thread.sp = (uint64_t)p + PGSIZE;//设置内核栈初始栈顶。task[i] 指向这一页底部，加上 PGSIZE 就是页顶。
        p->thread.sepc = USER_START;
        p->thread.sstatus = (csr_read(sstatus) & ~(uint64_t)SSTATUS_SPP &
                                   ~(uint64_t)SSTATUS_SIE) |
                                  SSTATUS_SPIE | SSTATUS_SUM;
        p->thread.sscratch = USER_END; //保存用户栈指针初始值。USER_END 是用户栈顶，栈向低地址增长
        p->thread.stval = 0;
        p->thread.scause = 0;

        p->pgd = setup_user_pagetable();
        p->mm = setup_user_mm();
        task[nr_tasks++] = p;
    }

    printk("...task_init done!\n");
}

void do_timer(void) {
    // 1. 如果当前线程时间片耗尽，则直接进行调度
    // 2. 否则将运行剩余时间减 1，若剩余时间仍然大于 0 则直接返回，否则进行调度
    if (current->counter > 0){
        current->counter --;
        if (current->counter > 0){
            return;
        }
    }
    schedule();
}

void schedule(void) {
    uint64_t max_counter = 0;
    struct task_struct *next = idle;
    for (size_t i = 1; i < nr_tasks; i ++){
        if (task[i]->counter > max_counter){
            max_counter = task[i]->counter;
            next = task[i];
        }
    }
    if (max_counter == 0){
        for (size_t i = 1; i < nr_tasks; i ++){
            task[i]->counter = task[i]->priority;
            printk("SET [PID = %lu, PRIORITY = %lu, COUNTER = %lu]\n",
                   task[i]->pid, task[i]->priority, task[i]->counter);
            if (task[i]->counter > max_counter){
                max_counter = task[i]->counter;
                next = task[i];
            }
        }
    }
    switch_to(next);
}

void switch_to(struct task_struct *next) {
    if (current == next){
        return;
    }
    printk("switch to [PID = %lu, PRIORITY = %lu, COUNTER = %lu]\n",
           next->pid, next->priority, next->counter);
    struct task_struct *prev = current;   
    current = next;
    __switch_to(prev, next);
}

long do_fork(struct pt_regs *regs) {
    if (nr_tasks >= NR_TASKS) {
        printk("do_fork: no free task slot\n");
        return -1;
    }

    struct task_struct *parent = current;
    struct task_struct *child = alloc_page();
    memcpy(child, parent, PGSIZE);

    uint64_t child_pid = nr_tasks;
    child->pid = child_pid;
    child->state = TASK_RUNNING;
    child->priority = rand() % (PRIORITY_MAX - PRIORITY_MIN + 1) + PRIORITY_MIN;
    child->counter = 0;
    child->pgd = setup_user_pagetable();
    child->mm = copy_mm(parent->mm);

    struct pt_regs *child_regs =
        (struct pt_regs *)((uint64_t)child + ((uint64_t)regs - (uint64_t)parent));
    child_regs->x[10] = 0;//a0=0,子进程返回0
    child_regs->sepc += 4;

    child->thread.ra = (uint64_t)ret_from_fork;
    child->thread.sp = (uint64_t)child_regs;//让子进程的内核栈指针指向自己的 pt_regs。ret_from_fork 要靠它恢复寄存器。
    child->thread.sepc = child_regs->sepc;

    printk("do_fork: %lu -> %lu\n", parent->pid, child_pid);
    share_present_pages(parent, child);//共享父进程已经实际映射的用户页，并设置 COW

    task[nr_tasks++] = child;
    regs->x[10] = child_pid;//父进程返回子进程的 PID
    return (long)child_pid;
}
