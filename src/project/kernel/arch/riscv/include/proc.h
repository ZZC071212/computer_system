#ifndef __PROC_H__
#define __PROC_H__

#include <stdint.h>

#define TASK_RUNNING 0 // 为了简化实验，所有的线程都只有一种状态

// 可自行修改的宏定义
#define NR_TASKS (1 + 4) // idle 线程 + 用户线程
#define PRIORITY_MIN 1
#define PRIORITY_MAX 10

// 线程状态结构
struct thread_struct {
  uint64_t ra;
  uint64_t sp;
  uint64_t s[12];
};

// 进程数据结构
struct task_struct {
  uint64_t pid;      // 进程 ID
  uint64_t state;    // 状态
  uint64_t priority; // 优先级
  uint64_t counter;  // 剩余时间

  struct thread_struct thread; // 线程结构
};

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

/**
 * @brief 空闲线程函数
 */
void dummy_task(void);

#endif
