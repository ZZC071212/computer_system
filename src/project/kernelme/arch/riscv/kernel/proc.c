#include <mm.h>
#include <proc.h>
#include <private_kdefs.h>
#include <printk.h>
#include <stdlib.h>

static struct task_struct *task[NR_TASKS]; // 线程数组，所有的线程都保存在此
static struct task_struct *idle;           // idle 线程
struct task_struct *current;               // 当前运行线程

void __dummy(void);
void __switch_to(struct task_struct *prev, struct task_struct *next);

// 在这里添加或实现这些函数：
// - void dummy_task(void);
void dummy_task(void) {
    unsigned local = 0;
    unsigned prev_cnt = 0;
    while (1) {
        if (current->counter != prev_cnt) {
        if (current->counter == 1) {
            // 若 priority 为 1，则线程可见的 counter 永远为 1（为什么？）
            // 通过设置 counter 为 0，避免信息无法打印的问题
            current->counter = 0;
        }
        prev_cnt = current->counter;
        printk("[P=%u] %u\n", current->pid, ++local);
        }
    }
}
// - void task_init(void);
void task_init(void) {
    srand(2025);

    // 1. 调用 alloc_page() 为 idle 分配一个物理页
    idle = alloc_page();
    // 2. 初始化 idle 线程：
    //   - state 为 TASK_RUNNING
    //   - pid 为 0
    //   - 由于其不参与调度，可以将 priority 和 counter 设为 0
    idle->state = TASK_RUNNING;
    idle->pid = 0;
    idle->priority = 0, idle->counter = 0;
    // 3. 将 current 和 task[0] 指向 idle
    current = idle;
    task[0] = idle;
    // 4. 初始化 task[1..NR_TASKS - 1]：
    //    - 分配一个物理页
    //    - state 为 TASK_RUNNING
    //    - pid 为对应线程在 task 数组中的索引
    //    - priority 为 rand() 产生的随机数，控制范围在 [PRIORITY_MIN, PRIORITY_MAX]
    //    - counter 为 0
    //    - 设置 thread_struct 中的 ra 和 sp：
    //      - ra 设置为 __dummy 的地址（见 4.3.2 节）
    //      - sp 设置为该线程申请的物理页的高地址
    for (int i = 1; i < NR_TASKS; i ++){
        task[i] = alloc_page();
        task[i]->state = TASK_RUNNING;
        task[i]->pid = i;
        uint64_t priority = rand() % (PRIORITY_MAX - PRIORITY_MIN + 1) + PRIORITY_MIN;
        task[i]->priority = priority;
        task[i]->counter = 0;

        task[i]->thread.ra = (uint64_t)__dummy;
        task[i]->thread.sp = (uint64_t)task[i] + PGSIZE;
    }

    printk("...task_init done!\n");
}
// - void do_timer(void);
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
// - void schedule(void);
void schedule(void) {
    uint64_t max_counter = 0;
    struct task_struct *next;
    for (int i = 1; i < NR_TASKS; i ++){
        if (task[i]->counter > max_counter){
            max_counter = task[i]->counter;
            next = task[i];
        }
    }
    if (max_counter == 0){
        for (int i = 1; i < NR_TASKS; i ++){
            task[i]->counter = task[i]->priority;
            // printk("SET [PID = %ld, PRIORITY = %ld, COUNTER = %ld]\n", task[i]->pid, task[i]->priority, task[i]->counter);
            if (task[i]->counter > max_counter){
                max_counter = task[i]->counter;
                next = task[i];
            }
        }
    }
    switch_to(next);
}
// - void switch_to(struct task_struct* next);
void switch_to(struct task_struct *next) {
    if (current == next){
        return;
    }
    // printk("switch to [PID = %ld, PRIORITY = %ld, COUNTER = %ld]\n", next->pid, next->priority, next->counter);
    struct task_struct *prev = current;   
    current = next;
    __switch_to(prev, next);
}
