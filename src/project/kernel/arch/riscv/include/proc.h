#ifndef __PROC_H__
#define __PROC_H__

#include <stddef.h>
#include <stdint.h>

#define TASK_RUNNING 0 // 为了简化实验，所有的线程都只有一种状态

// 可自行修改的宏定义
#define NR_TASKS (1 + 8) // idle 线程 + 最多 8 个用户进程
#define PRIORITY_MIN 1
#define PRIORITY_MAX 10

typedef uint64_t *pagetable_t;

#define VM_READ 0x01
#define VM_WRITE 0x02
#define VM_EXEC 0x04
#define VM_ANON 0x08

struct mm_struct;

struct vm_area_struct {
  struct mm_struct *vm_mm;
  void *vm_start;
  void *vm_end;
  unsigned vm_flags;
  struct vm_area_struct *vm_prev;
  struct vm_area_struct *vm_next;
};

struct mm_struct {
  struct vm_area_struct *mmap;
};

// 中断处理所需寄存器堆
struct pt_regs {
  uint64_t x[32];
  uint64_t sepc;
};

// 线程状态结构
struct thread_struct {
  uint64_t ra;
  uint64_t sp;
  uint64_t s[12];

  uint64_t sepc;
  uint64_t sstatus;
  uint64_t sscratch;
  uint64_t stval;
  uint64_t scause;
};

// 进程数据结构
struct task_struct {
  uint64_t pid;      // 进程 ID
  uint64_t state;    // 状态
  uint64_t priority; // 优先级
  uint64_t counter;  // 剩余时间

  struct thread_struct thread; // 线程结构

  pagetable_t pgd; // 页表

  struct mm_struct *mm;
};

extern struct task_struct *current;

/**
 * @brief 进程初始化函数
 */
void task_init(void);

/**
 * @brief 时钟中断处理函数
 */
void do_timer(void);

/**
 * @brief 进程调度函数
 */
void schedule(void);

/**
 * @brief 切换到下一个进程
 *
 * @param next 要切换到的进程
 */
void switch_to(struct task_struct *next);

//遍历mm链表，寻找va所在的vma
struct vm_area_struct *find_vma(struct mm_struct *mm, void *va);
//新建vm_area_struct结构体，根据传入的参数对结构体进行赋值，并添加到mm指向的vma链表中
void *do_mmap(struct mm_struct *mm, void *va, size_t len, unsigned flags);

long do_fork(struct pt_regs *regs);

#endif
